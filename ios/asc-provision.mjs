#!/usr/bin/env node
// Creates the signing assets this app needs on the Apple Developer account:
// a bundle id, an Apple Distribution certificate, and an App Store provisioning
// profile. Everything the App Store Connect API can do without a browser.
//
// Usage:
//   node asc-provision.mjs status                 # what already exists
//   node asc-provision.mjs bundle-id
//   node asc-provision.mjs certificate --csr <path to .csr>
//   node asc-provision.mjs profile
//
// Credentials come from the environment (the toddler-games .env holds them):
//   APPSTORECONNECT_KEY_ID, APPSTORECONNECT_ISSUER_ID, APPSTORECONNECT_P8
//
// Writes nothing secret to disk; the certificate and profile land in ./build.

import { createSign, createPrivateKey } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';

const API = 'https://api.appstoreconnect.apple.com/v1';
const BUNDLE_ID = 'com.bersling.redwedgetimer';
const APP_NAME = 'Red Wedge Timer';
const PROFILE_NAME = 'Red Wedge Timer App Store';

function requireEnv(name) {
	const value = process.env[name];
	if (!value) throw new Error(`missing ${name}`);
	return value;
}

async function token() {
	const keyId = requireEnv('APPSTORECONNECT_KEY_ID');
	const issuerId = requireEnv('APPSTORECONNECT_ISSUER_ID');
	const p8 = await readFile(requireEnv('APPSTORECONNECT_P8'), 'utf8');

	const now = Math.floor(Date.now() / 1000);
	const encode = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
	const head = encode({ alg: 'ES256', kid: keyId, typ: 'JWT' });
	const body = encode({ iss: issuerId, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' });

	const signer = createSign('SHA256');
	signer.update(`${head}.${body}`);
	const signature = signer.sign(
		{ key: createPrivateKey(p8), dsaEncoding: 'ieee-p1363' }
	);
	return `${head}.${body}.${signature.toString('base64url')}`;
}

async function call(method, path, body) {
	const response = await fetch(`${API}${path}`, {
		method,
		headers: {
			Authorization: `Bearer ${await token()}`,
			'Content-Type': 'application/json',
		},
		body: body ? JSON.stringify(body) : undefined,
	});
	const text = await response.text();
	const json = text ? JSON.parse(text) : {};
	if (!response.ok) {
		const detail = (json.errors ?? [])
			.map((e) => `${e.title}: ${e.detail}`)
			.join('\n  ');
		throw new Error(`${method} ${path} -> ${response.status}\n  ${detail || text}`);
	}
	return json;
}

async function findBundleId() {
	const found = await call('GET', `/bundleIds?filter[identifier]=${BUNDLE_ID}&limit=1`);
	return found.data?.[0];
}

async function status() {
	const bundle = await findBundleId();
	console.log('bundle id :', bundle ? `${bundle.id} (${bundle.attributes.name})` : 'not registered');

	const certs = await call('GET', '/certificates?limit=50');
	for (const c of certs.data) {
		console.log('cert      :', c.attributes.certificateType, '|', c.attributes.displayName,
			'| expires', (c.attributes.expirationDate ?? '').slice(0, 10), '|', c.id);
	}

	const profiles = await call('GET', '/profiles?limit=50');
	for (const p of profiles.data) {
		console.log('profile   :', p.attributes.profileType, '|', p.attributes.name, '|', p.attributes.profileState);
	}
}

async function createBundleId() {
	const existing = await findBundleId();
	if (existing) {
		console.log('bundle id already registered:', existing.id);
		return existing;
	}
	const made = await call('POST', '/bundleIds', {
		data: {
			type: 'bundleIds',
			attributes: { identifier: BUNDLE_ID, name: APP_NAME, platform: 'IOS' },
		},
	});
	console.log('registered bundle id:', made.data.id);
	return made.data;
}

async function createCertificate(csrPath) {
	const csr = await readFile(csrPath, 'utf8');
	const made = await call('POST', '/certificates', {
		data: {
			type: 'certificates',
			attributes: { certificateType: 'DISTRIBUTION', csrContent: csr },
		},
	});
	const { id, attributes } = made.data;
	await mkdir('build', { recursive: true });
	await writeFile('build/distribution.cer', Buffer.from(attributes.certificateContent, 'base64'));
	console.log('created certificate:', id, '->  build/distribution.cer');
	return made.data;
}

async function createProfile() {
	const bundle = await findBundleId();
	if (!bundle) throw new Error('register the bundle id first');

	const certs = await call('GET', '/certificates?limit=50');
	const distribution = certs.data.filter((c) => c.attributes.certificateType === 'DISTRIBUTION');
	if (distribution.length === 0) throw new Error('no distribution certificate on the account');

	const made = await call('POST', '/profiles', {
		data: {
			type: 'profiles',
			attributes: { name: PROFILE_NAME, profileType: 'IOS_APP_STORE' },
			relationships: {
				bundleId: { data: { type: 'bundleIds', id: bundle.id } },
				certificates: { data: distribution.map((c) => ({ type: 'certificates', id: c.id })) },
			},
		},
	});
	await mkdir('build', { recursive: true });
	await writeFile(
		'build/RedWedgeTimer.mobileprovision',
		Buffer.from(made.data.attributes.profileContent, 'base64')
	);
	console.log('created profile:', made.data.attributes.name, '->  build/RedWedgeTimer.mobileprovision');
	return made.data;
}

const [command, ...rest] = process.argv.slice(2);
const flag = (name) => {
	const at = rest.indexOf(`--${name}`);
	return at === -1 ? undefined : rest[at + 1];
};

try {
	switch (command) {
		case 'status': await status(); break;
		case 'bundle-id': await createBundleId(); break;
		case 'certificate': await createCertificate(flag('csr') ?? 'build/distribution.csr'); break;
		case 'profile': await createProfile(); break;
		default:
			console.error('commands: status | bundle-id | certificate --csr <path> | profile');
			process.exit(2);
	}
} catch (error) {
	console.error(String(error.message ?? error));
	process.exit(1);
}
