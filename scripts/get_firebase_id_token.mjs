#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const DEFAULT_API_BASE_URL = 'https://api-3fyxl76mkq-uc.a.run.app';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const firebaseOptionsPath = path.join(
  repoRoot,
  'shavtzak',
  'lib',
  'firebase_options.dart',
);

function printUsage() {
  console.error(`Usage:
  node scripts/get_firebase_id_token.mjs --unique-key <UNIQUE_KEY> --passcode <PASSCODE> [options]

Options:
  --environment <production|test>  Sign in against the selected environment. Default: production
  --api-base-url <URL>             Override the backend base URL.
  --json                           Print a JSON object instead of only the ID token.
  --help                           Show this help message.

Examples:
  node scripts/get_firebase_id_token.mjs --unique-key abc --passcode 1234
  node scripts/get_firebase_id_token.mjs --unique-key abc --passcode 1234 --environment test --json
`);
}

function parseArgs(argv) {
  const options = {
    environment: 'production',
    apiBaseUrl: DEFAULT_API_BASE_URL,
    json: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    if (arg === '--help') {
      options.help = true;
      continue;
    }

    if (arg === '--json') {
      options.json = true;
      continue;
    }

    const nextValue = argv[index + 1];
    const consumeNext = () => {
      if (nextValue == null || nextValue.startsWith('--')) {
        throw new Error(`Missing value for ${arg}`);
      }
      index += 1;
      return nextValue;
    };

    switch (arg) {
      case '--unique-key':
      case '--uniqueKey':
        options.uniqueKey = consumeNext();
        break;
      case '--passcode':
        options.passcode = consumeNext();
        break;
      case '--environment':
        options.environment = consumeNext();
        break;
      case '--api-base-url':
      case '--base-url':
        options.apiBaseUrl = consumeNext();
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function readFirebaseApiKey() {
  const contents = fs.readFileSync(firebaseOptionsPath, 'utf8');
  const match = contents.match(/apiKey:\s*'([^']+)'/);

  if (match == null || match[1] == null || match[1].length === 0) {
    throw new Error(`Could not find Firebase apiKey in ${firebaseOptionsPath}`);
  }

  return match[1];
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const rawText = await response.text();
  let parsedBody = null;

  if (rawText.length > 0) {
    try {
      parsedBody = JSON.parse(rawText);
    } catch (error) {
      throw new Error(`Invalid JSON response from ${url}: ${rawText}`);
    }
  }

  if (!response.ok) {
    const message =
      parsedBody?.error ??
      parsedBody?.message ??
      parsedBody?.details ??
      response.statusText ??
      'Request failed';
    throw new Error(`${response.status} ${message}`);
  }

  return parsedBody ?? {};
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printUsage();
    return;
  }

  if (options.uniqueKey == null || options.uniqueKey.length === 0) {
    throw new Error('Missing required --unique-key');
  }

  if (options.passcode == null || options.passcode.length === 0) {
    throw new Error('Missing required --passcode');
  }

  if (options.environment !== 'production' && options.environment !== 'test') {
    throw new Error('Environment must be either "production" or "test"');
  }

  const apiKey = readFirebaseApiKey();
  const signInResponse = await postJson(
    `${options.apiBaseUrl.replace(/\/$/, '')}/auth/sign-in`,
    {
      uniqueKey: options.uniqueKey,
      passcode: options.passcode,
      environment: options.environment,
    },
  );

  const customToken = signInResponse.customToken;
  if (typeof customToken !== 'string' || customToken.length === 0) {
    throw new Error('Backend did not return a customToken');
  }

  const tokenResponse = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
    {
      token: customToken,
      returnSecureToken: true,
    },
  );

  const output = {
    idToken: tokenResponse.idToken,
    refreshToken: tokenResponse.refreshToken,
    expiresIn: tokenResponse.expiresIn,
    memberId: signInResponse.memberId,
    uniqueKey: signInResponse.uniqueKey,
    isAdmin: signInResponse.isAdmin === true,
    environment: options.environment,
  };

  if (typeof output.idToken !== 'string' || output.idToken.length === 0) {
    throw new Error('Firebase Auth did not return an idToken');
  }

  if (options.json) {
    console.log(JSON.stringify(output, null, 2));
    return;
  }

  console.log(output.idToken);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
