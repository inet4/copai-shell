"""Clipboard-to-Responses bridge, following inet4/copai's prompt and model."""
import base64
import json
import os
from pathlib import Path
import shlex
import subprocess
import urllib.error
import urllib.request

PROMPT = (
    "You are a networking specialist, please give the correct answer to the following "
    "question. If it is in German, then answer in German. If there are options provided "
    "for the question, just return the index of the correct answer: "
)


def read_settings(path):
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('sk-'):
            values['OPENAI_API_KEY'] = line
            continue
        if line.startswith('export '):
            line = line[7:]
        name, sep, value = line.partition('=')
        if sep:
            parts = shlex.split(value, comments=True)
            values[name.strip()] = ' '.join(parts)
    key = values.get('OPENAI_API_KEY') or values.get('OPENAI_KEY') or values.get('COPAI_API_KEY')
    if not key:
        raise ValueError('No API key found in copai.env.')
    return key, os.environ.get('COPAI_MODEL') or values.get('COPAI_MODEL', 'gpt-5-nano')


def clipboard(*args):
    return subprocess.run(['wl-paste', *args], check=True, capture_output=True, timeout=10).stdout


def make_input():
    types = clipboard('--list-types').decode().splitlines()
    image_type = next((t for t in types if t in ('image/png', 'image/jpeg', 'image/webp', 'image/gif')), None)
    if image_type:
        data = clipboard('--type', image_type)
        if len(data) > 20 * 1024 * 1024:
            raise ValueError('Clipboard image is too large (maximum 20 MiB).')
        return [{'role': 'user', 'content': [
            {'type': 'input_text', 'text': PROMPT + 'Answer the question in this image.'},
            {'type': 'input_image', 'image_url': 'data:' + image_type + ';base64,' + base64.b64encode(data).decode()},
        ]}]
    text = clipboard('--no-newline', '--type', 'text').decode().strip()
    if not text:
        raise ValueError('Copy a question or screenshot first.')
    return PROMPT + text


def answer():
    key, model = read_settings(Path(os.environ.get('COPAI_ENV_FILE', str(Path.home() / 'documents/licenses/copai.env'))))
    request = urllib.request.Request(
        'https://api.openai.com/v1/responses',
        data=json.dumps({'model': model, 'input': make_input()}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        data = json.load(response)
    texts = [part['text'] for item in data.get('output', []) if item.get('type') == 'message'
             for part in item.get('content', []) if part.get('type') == 'output_text' and part.get('text')]
    if data.get('status') != 'completed' or not texts:
        raise ValueError('No complete answer returned. Try submitting again.')
    return '\n\n'.join(texts)


def main():
    try:
        result = {'text': answer()}
    except urllib.error.HTTPError as exc:
        result = {'text': f'OpenAI request failed (HTTP {exc.code}). Check your key, quota, and model.'}
    except (urllib.error.URLError, TimeoutError):
        result = {'text': 'Request timed out or the network is unavailable. Try again.'}
    except subprocess.SubprocessError:
        result = {'text': 'Cannot read clipboard. Copy a question or image first.'}
    except OSError:
        result = {'text': 'Could not read copai.env or access the clipboard helper.'}
    except (ValueError, KeyError):
        result = {'text': 'Invalid key file, empty clipboard, oversized image, or incomplete response.'}
    print(json.dumps(result))


if __name__ == '__main__':
    main()
