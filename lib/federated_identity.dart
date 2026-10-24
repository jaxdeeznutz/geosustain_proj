import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_runtime.dart';

class FirebaseIdentity {
  static Future<void>? _google;
  static bool get configured => FirebaseRuntime.configured;
  static bool get googleConfigured =>
      configured && (kIsWeb || FirebaseRuntime.googleWebClientId.isNotEmpty);

  static String errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-phone-number' =>
          'Enter a valid phone number with its country code.',
        'invalid-verification-code' =>
          'Incorrect SMS code. Check the message and try again.',
        'session-expired' ||
        'code-expired' => 'The SMS code expired. Request a new code.',
        'too-many-requests' || 'quota-exceeded' =>
          'Too many verification attempts. Please try again later.',
        'popup-closed-by-user' ||
        'cancelled-popup-request' => 'Sign-in was cancelled.',
        'network-request-failed' =>
          'Check your internet connection and try again.',
        _ => 'The verification service is unavailable. Please try again later.',
      };
    }
    if (error is GoogleSignInException) {
      return 'Google sign-in was cancelled or could not finish. Try again or use your password.';
    }
    if (error is TimeoutException) {
      return 'Verification timed out. Check your connection and try again.';
    }
    return 'Verification could not complete. Please try again.';
  }

  static Future<String> googleProof() async {
    if (!googleConfigured) {
      throw StateError(
        'Google sign-in is temporarily unavailable. Use your email and password.',
      );
    }
    final auth = FirebaseAuth.instanceFor(
      app: await FirebaseRuntime.initialize(),
    );
    UserCredential result;
    if (kIsWeb) {
      result = await auth.signInWithPopup(
        GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
      );
    } else {
      _google ??= GoogleSignIn.instance.initialize(
        serverClientId: FirebaseRuntime.googleWebClientId,
      );
      await _google;
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google did not return a sign-in proof. Try again.');
      }
      result = await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    }
    final token = await result.user?.getIdToken(true);
    if (token == null) {
      throw StateError('Sign-in proof is unavailable. Try again.');
    }
    return token;
  }

  static Future<PhoneProofChallenge> startPhone(String phone) async {
    final auth = FirebaseAuth.instanceFor(
      app: await FirebaseRuntime.phoneApp(),
    );
    await auth.signOut();
    final challenge = PhoneProofChallenge._(auth);
    if (kIsWeb) {
      challenge.web = await auth.signInWithPhoneNumber(phone);
      return challenge;
    }
    final completed = Completer<PhoneProofChallenge>();
    await auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        try {
          final result = await auth.signInWithCredential(credential);
          challenge.automaticToken = await result.user?.getIdToken(true);
          if (!completed.isCompleted) completed.complete(challenge);
        } catch (error) {
          if (!completed.isCompleted) completed.completeError(error);
        }
      },
      verificationFailed: (error) {
        if (!completed.isCompleted) completed.completeError(error);
      },
      codeSent: (id, _) {
        challenge.verificationId = id;
        if (!completed.isCompleted) completed.complete(challenge);
      },
      codeAutoRetrievalTimeout: (id) {
        challenge.verificationId = id;
      },
    );
    return completed.future.timeout(const Duration(seconds: 60));
  }

  static Future<void> signOut() async {
    for (final app in Firebase.apps.where(
      (a) => a.name == '[DEFAULT]' || a.name == 'geosustain-phone-proof',
    )) {
      try {
        await FirebaseAuth.instanceFor(app: app).signOut();
      } catch (_) {
        /* App session is independently revoked. */
      }
    }
    if (!kIsWeb && _google != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        /* Local app token is still cleared. */
      }
    }
  }
}

class PhoneProofChallenge {
  PhoneProofChallenge._(this.auth);
  final FirebaseAuth auth;
  String? verificationId;
  String? automaticToken;
  ConfirmationResult? web;
  Future<String> confirm(String code) async {
    if (automaticToken != null) return automaticToken!;
    final result = web != null
        ? await web!.confirm(code)
        : await auth.signInWithCredential(
            PhoneAuthProvider.credential(
              verificationId: verificationId!,
              smsCode: code,
            ),
          );
    final token = await result.user?.getIdToken(true);
    if (token == null) {
      throw StateError(
        'Phone verification proof is unavailable. Request a new code.',
      );
    }
    return token;
  }

  Future<void> close() => auth.signOut();
}
