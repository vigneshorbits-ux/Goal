import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _referralEmailController = TextEditingController();

  // Native Location Controller
  final _nativeLocationController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _showReferralField = false;
  bool _isCheckingUsername = false;
  String? _usernameError;
  
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _privacyPolicyAccepted = false;

  @override
  void initState() {
    super.initState();
    _checkUserLoggedIn();
    _usernameController.addListener(_onUsernameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ModalRoute.of(context)?.isCurrent ?? false) {}
    });
  }

  void _checkUserLoggedIn() {
    final user = _auth.currentUser;
    if (user != null) {
      _navigateToHome(user.uid);
    }
  }

  void _onUsernameChanged() {
    if (!_isLogin && _usernameController.text.isNotEmpty) {
      _debounceUsernameCheck();
    }
  }

  // Debounce username checking to avoid too many API calls
  Timer? _debounceTimer;
  void _debounceUsernameCheck() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _checkUsernameAvailability(_usernameController.text.trim());
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (username.isEmpty) return;
    
    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    try {
      // Check if username already exists
      final querySnapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          if (querySnapshot.docs.isNotEmpty) {
            _usernameError = 'Username already taken';
          } else {
            _usernameError = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _usernameError = 'Error checking username';
        });
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _mobileController.dispose();
    _referralEmailController.dispose();
    _nativeLocationController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Check username availability one more time before registration
    if (!_isLogin) {
      if (_usernameError != null || _isCheckingUsername) {
        _showErrorSnackbar('Please choose a valid username');
        return;
      }
      
      // Final username check
      final username = _usernameController.text.trim().toLowerCase();
      final usernameCheck = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      
      if (usernameCheck.docs.isNotEmpty) {
        setState(() {
          _usernameError = 'Username already taken';
        });
        _showErrorSnackbar('Username is already taken. Please choose another.');
        return;
      }
    }
    
    setState(() => _isLoading = true);
    FocusScope.of(context).unfocus();
    
    try {
      if (_isLogin) {
        await _handleLogin();
      } else {
        await _handleRegistration();
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackbar(_getErrorMessage(e));
    } catch (e) {
      _showErrorSnackbar('An error occurred: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );
    if (!credential.user!.emailVerified) {
      _showErrorSnackbar('Please verify your email before logging in');
      await _auth.signOut();
      return;
    }
    await _navigateToHome(credential.user!.uid);
  }

  Future<void> _handleRegistration() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );
    await credential.user?.sendEmailVerification();

    var uuid = const Uuid();
    String uniqueUserId = uuid.v4();
    String username = _usernameController.text.trim().toLowerCase();

    String? referrerUid;
    bool isReferred = false;
    if (_referralEmailController.text.trim().isNotEmpty) {
      referrerUid = await _processReferral(_referralEmailController.text.trim());
      if (referrerUid != null) {
        isReferred = true;
      }
    }

    // Build Firestore data map
    final Map<String, dynamic> userMap = {
      'uid': credential.user?.uid,
      'uniqueId': uniqueUserId,
      'username': username, // Store username in lowercase for consistency
      'displayUsername': _usernameController.text.trim(), // Store original case for display
      'mobile': _mobileController.text.trim(),
      'email': _emailController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'rewards': 0,
      'isReferred': isReferred,
      'referredBy': referrerUid,
      'referralCount': 0,
      'hasSpecialSpin': isReferred,
      'specialSpinUsed': false,
    };
    
    // Only add nativeLocation if filled
    if (_nativeLocationController.text.trim().isNotEmpty) {
      userMap['nativeLocation'] = _nativeLocationController.text.trim();
    }

    // Use a transaction to ensure username uniqueness
    await _firestore.runTransaction((transaction) async {
      // Check one more time in transaction
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      
      if (usernameQuery.docs.isNotEmpty) {
        throw Exception('Username already taken');
      }
      
      // Create user document
      final userRef = _firestore.collection('users').doc(credential.user?.uid);
      transaction.set(userRef, userMap);
    });

    if (referrerUid != null) {
      await _updateReferrerData(referrerUid, credential.user!.uid);
    }

    _showSuccessSnackbar('Verification email sent! Please check your inbox');
    _toggleAuthMode();
  }

  Future<String?> _processReferral(String referralEmail) async {
    try {
      if (referralEmail.toLowerCase() == _emailController.text.trim().toLowerCase()) {
        _showErrorSnackbar('You cannot refer yourself!');
        return null;
      }
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: referralEmail.toLowerCase())
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) {
        _showErrorSnackbar('Referral email not found. Please check and try again.');
        return null;
      }
      final referrerDoc = querySnapshot.docs.first;
      _showSuccessSnackbar('Valid referral! You\'ll get a special spin bonus!');
      return referrerDoc.id;
    } catch (e) {
      _showErrorSnackbar('Error processing referral: ${e.toString()}');
      return null;
    }
  }

  Future<void> _updateReferrerData(String referrerUid, String newUserUid) async {
    try {
      final batch = _firestore.batch();
      final referrerRef = _firestore.collection('users').doc(referrerUid);
      batch.update(referrerRef, {
        'referralCount': FieldValue.increment(1),
        'hasSpecialSpin': true,
        'rewards': FieldValue.increment(100),
      });
      final referralRef = referrerRef.collection('referrals').doc(newUserUid);
      batch.set(referralRef, {
        'referredUserUid': newUserUid,
        'referredUserEmail': _emailController.text.trim(),
        'referredAt': FieldValue.serverTimestamp(),
        'bonusGranted': true,
      });
      await batch.commit();
    } catch (e) {
      print('Error updating referrer data: $e');
    }
  }

  String _getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Email already registered';
      case 'weak-password':
        return 'Password too weak (min 6 chars)';
      case 'user-not-found':
        return 'User not found';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-email':
        return 'Invalid email format';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }

  Future<void> _navigateToHome(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final isAdmin = userDoc.data()?['isAdmin'] == true;
      if (!mounted) return;
      if (isAdmin) {
        Navigator.of(context).pushReplacementNamed('/admin');
      } else {
        Navigator.of(context).pushReplacementNamed('/HomeScreen');
      }
    } catch (e) {
      debugPrint('Error checking user role: $e');
      _showErrorSnackbar("Failed to determine user role. Please try again.");
    }
  }

  void _toggleAuthMode() {
    _formKey.currentState?.reset();
    setState(() {
      _isLogin = !_isLogin;
      _showReferralField = false;
      _usernameError = null;
      _isCheckingUsername = false;
    });
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(theme),
                const SizedBox(height: 32),
                if (!_isLogin) ...[
                  _buildUsernameField(theme),
                  const SizedBox(height: 16),
                  _buildMobileField(theme),
                  const SizedBox(height: 16),
                  _buildNativeLocationField(theme),
                  const SizedBox(height: 16),
                ],
                _buildEmailField(theme),
                const SizedBox(height: 16),
                _buildPasswordField(theme),
                const SizedBox(height: 16),
                if (!_isLogin) ...[
                  _buildReferralSection(theme),
                  const SizedBox(height: 16),
                  _buildPrivacyPolicyCheckbox(),
                  const SizedBox(height: 16),
                ],
                _buildAuthButton(theme),
                const SizedBox(height: 16),
                _buildToggleAuthButton(theme),
                if (_isLogin) ...[
                  const SizedBox(height: 16),
                  _buildForgotPasswordButton(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferralSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.card_giftcard,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Have a referral?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  _showReferralField = !_showReferralField;
                });
              },
              child: Text(
                _showReferralField ? 'Hide' : 'Enter Code',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (_showReferralField) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎁 Get a special spin bonus!',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _referralEmailController,
                  decoration: InputDecoration(
                    labelText: 'Referrer\'s Email',
                    hintText: 'Enter your friend\'s email',
                    prefixIcon: const Icon(Icons.person_add_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty && !value.contains('@')) {
                      return 'Enter valid email';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPrivacyPolicyCheckbox() {
    return CheckboxListTile(
      value: _privacyPolicyAccepted,
      onChanged: (newValue) {
        setState(() => _privacyPolicyAccepted = newValue ?? false);
      },
      title: GestureDetector(
        onTap: () {
          Navigator.pushNamed(context, '/privacy-policy');
        },
        child: RichText(
          text: const TextSpan(
            text: 'I agree to the ',
            style: TextStyle(color: Colors.black),
            children: [
              TextSpan(
                text: 'Privacy Policy',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        Icon(
          Icons.psychology_rounded,
          size: 100,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          _isLogin ? 'Welcome !' : 'Create Account',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isLogin 
              ? 'Sign in to continue your learning journey'
              : 'Start your learning adventure with us',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: 'Username',
            hintText: 'Choose a unique username',
            prefixIcon: const Icon(Icons.person_outline),
            suffixIcon: _isCheckingUsername
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _usernameError == null && _usernameController.text.isNotEmpty
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : _usernameError != null
                        ? const Icon(Icons.error, color: Colors.red)
                        : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            errorText: _usernameError,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a username';
            }
            if (value.length < 3) {
              return 'Username must be at least 3 characters';
            }
            if (value.length > 20) {
              return 'Username must be less than 20 characters';
            }
            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
              return 'Username can only contain letters, numbers, and underscores';
            }
            if (_usernameError != null) {
              return _usernameError;
            }
            return null;
          },
        ),
        const SizedBox(height: 4),
        Text(
          'Username must be unique and 3-20 characters (letters, numbers, _ only)',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileField(ThemeData theme) {
    return TextFormField(
      controller: _mobileController,
      decoration: InputDecoration(
        labelText: 'Mobile Number',
        prefixIcon: const Icon(Icons.phone_iphone_rounded),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: TextInputType.number,
      maxLength: 10,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Enter mobile number';
        }
        if (!RegExp(r'^[0-9]{10}$').hasMatch(value)) {
          return 'Enter a valid 10-digit number';
        }
        return null;
      },
    );
  }

  Widget _buildNativeLocationField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _nativeLocationController,
          decoration: InputDecoration(
            labelText: 'Native Location (optional)',
            prefixIcon: const Icon(Icons.location_on),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This helps us give you the best battle experience only. (Optional)',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildEmailField(ThemeData theme) {
    return TextFormField(
      controller: _emailController,
      decoration: InputDecoration(
        labelText: 'Email',
        prefixIcon: const Icon(Icons.email_outlined),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: TextInputType.emailAddress,
      validator: (value) => value!.contains('@') ? null : 'Enter valid email',
    );
  }

  Widget _buildPasswordField(ThemeData theme) {
    return TextFormField(
      controller: _passwordController,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          icon: Icon(_passwordVisible 
              ? Icons.visibility_outlined 
              : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      obscureText: !_passwordVisible,
      validator: (value) => value!.length >= 6 
          ? null 
          : 'Minimum 6 characters required',
    );
  }

  Widget _buildAuthButton(ThemeData theme) {
    bool isDisabled = _isLoading || 
                     (!_isLogin && !_privacyPolicyAccepted) ||
                     (!_isLogin && _isCheckingUsername) ||
                     (!_isLogin && _usernameError != null);
                     
    return ElevatedButton(
      onPressed: isDisabled ? null : _authenticate,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _isLogin ? 'Sign In' : 'Create Account',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color.fromARGB(255, 198, 230, 14),
              ),
            ),
    );
  }

  Widget _buildToggleAuthButton(ThemeData theme) {
    return TextButton(
      onPressed: _isLoading ? null : _toggleAuthMode,
      child: RichText(
        text: TextSpan(
          text: _isLogin 
              ? "Don't have an account? "
              : "Already have an account? ",
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: _isLogin ? 'Register' : 'Login',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForgotPasswordButton(ThemeData theme) {
    return TextButton(
      onPressed: _isLoading
          ? null
          : () => Navigator.pushNamed(context, '/forgot-password'),
      child: Text(
        'Forgot Password?',
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}