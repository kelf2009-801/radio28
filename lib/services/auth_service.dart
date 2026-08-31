import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Handles the on-device identity:
/// - RSA-2048 keypair generated once on first launch (stored in secure storage)
/// - challenge-response login: server sends nonce, we sign it, server verifies with our public key
/// - no phone / email / password — account IS the key
class AuthService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kPrivKey = 'rsa_priv_pem';
  static const _kPubKey = 'rsa_pub_pem';
  static const _kUserId = 'user_id';
  static const _kSession = 'session_token';
  static const _kProfile = 'profile_json';
  static const _kServerUrl = 'server_url';

  pc.RSAPrivateKey? _priv;
  pc.RSAPublicKey? _pub;
  Profile? profile;
  String? sessionToken;

  static const defaultServer = String.fromEnvironment(
    'RADIO_SERVER',
    defaultValue: 'http://192.168.0.191:8000', // домашний комп Андрея (LAN); на VPS заменю при сборке
  );

  Future<String> get serverUrl async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerUrl) ?? defaultServer;
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, url.trim());
  }

  bool get hasIdentity => _priv != null && profile != null;

  /// Load existing identity or return false if first run.
  Future<bool> load() async {
    try {
      final privPem = await _storage.read(key: _kPrivKey);
      final pubPem = await _storage.read(key: _kPubKey);
      final profJson = await _storage.read(key: _kProfile);
      sessionToken = await _storage.read(key: _kSession);
      if (privPem == null || pubPem == null || profJson == null) return false;
      _priv = _parsePrivateKey(privPem);
      _pub = _parsePublicKey(pubPem);
      profile = Profile.decode(profJson);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// First-run registration: generate keypair, register on server.
  Future<Profile> register({
    required String callsign,
    String? route,
  }) async {
    final pair = _generateRsaKeyPair();
    _priv = pair.privateKey as pc.RSAPrivateKey;
    _pub = pair.publicKey as pc.RSAPublicKey;
    final userId = const Uuid().v4();
    final pubPem = _encodePublicKeyToPem(_pub!);
    final privPem = _encodePrivateKeyToPem(_priv!);

    profile = Profile(
      userId: userId,
      callsign: callsign.trim(),
      route: route?.trim().isEmpty ?? true ? null : route!.trim(),
      publicKeyPem: pubPem,
    );

    await _storage.write(key: _kPrivKey, value: privPem);
    await _storage.write(key: _kPubKey, value: pubPem);
    await _storage.write(key: _kUserId, value: userId);
    await _storage.write(key: _kProfile, value: profile!.encode());
    return profile!;
  }

  /// challenge-response: GET /auth/challenge?user_id=... -> sign nonce -> POST /auth/login
  String signChallenge(String nonce) {
    if (_priv == null) throw StateError('no identity');
    final signer = pc.RSASigner(pc.SHA256Digest(), '0609608648016503040201')
      ..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(_priv!));
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(nonce)));
    return base64Encode(sig.bytes);
  }

  Future<void> saveSession(String token) async {
    sessionToken = token;
    await _storage.write(key: _kSession, value: token);
  }

  Future<void> logout() async {
    sessionToken = null;
    profile = null;
    await _storage.delete(key: _kSession);
    await _storage.delete(key: _kProfile);
    // keys stay: same account after re-login. Full wipe happens on app uninstall.
  }

  /// Verify a server knows our key: helper for testing.
  String fingerprint() {
    final pub = _storage.read(key: _kPubKey);
    return sha256.convert(utf8.encode(pub.toString())).toString().substring(0, 12);
  }

  // ---- RSA helpers ----

  pc.AsymmetricKeyPair<pc.PublicKey, pc.PrivateKey> _generateRsaKeyPair() {
    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        _secureRandom(),
      ));
    return keyGen.generateKeyPair();
  }

  pc.SecureRandom _secureRandom() {
    final rnd = pc.SecureRandom('Fortuna')
      ..seed(pc.KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch & 0xff))));
    return rnd;
  }

  String _encodePublicKeyToPem(pc.RSAPublicKey key) {
    // SubjectPublicKeyInfo would need full ASN.1; we use a compact raw form:
    // modulus+exponent base64 — server reconstructs. PEM-ish wrapper keeps it readable.
    final n = base64Encode(_bigIntToBytes(key.modulus!));
    final e = base64Encode(_bigIntToBytes(key.exponent!));
    return '-----BEGIN RSA PUBLIC KEY-----\n$n\n$e\n-----END RSA PUBLIC KEY-----';
  }

  String _encodePrivateKeyToPem(pc.RSAPrivateKey key) {
    final n = base64Encode(_bigIntToBytes(key.modulus!));
    final d = base64Encode(_bigIntToBytes(key.privateExponent!));
    final p = base64Encode(_bigIntToBytes(key.p!));
    final q = base64Encode(_bigIntToBytes(key.q!));
    final e = base64Encode(_bigIntToBytes(key.exponent!));
    return '-----BEGIN RSA PRIVATE KEY-----\n$n\n$d\n$p\n$q\n$e\n-----END RSA PRIVATE KEY-----';
  }

  pc.RSAPublicKey _parsePublicKey(String pem) {
    final lines = pem.split('\n').where((l) => !l.startsWith('-----') && l.isNotEmpty).toList();
    final n = _bytesToBigInt(base64Decode(lines[0]));
    final e = _bytesToBigInt(base64Decode(lines[1]));
    return pc.RSAPublicKey(n, e);
  }

  pc.RSAPrivateKey _parsePrivateKey(String pem) {
    final lines = pem.split('\n').where((l) => !l.startsWith('-----') && l.isNotEmpty).toList();
    final n = _bytesToBigInt(base64Decode(lines[0]));
    final d = _bytesToBigInt(base64Decode(lines[1]));
    final p = _bytesToBigInt(base64Decode(lines[2]));
    final q = _bytesToBigInt(base64Decode(lines[3]));
    return pc.RSAPrivateKey(n, d, p, q);
  }

  Uint8List _bigIntToBytes(BigInt v) {
    var hex = v.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  BigInt _bytesToBigInt(Uint8List bytes) {
    var hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return BigInt.parse(hex.isEmpty ? '0' : hex, radix: 16);
  }
}
