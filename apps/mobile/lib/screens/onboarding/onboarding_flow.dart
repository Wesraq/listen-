import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../support_legal.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { welcome, createAccount, signIn, market, interests }

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step step = _Step.welcome;
  final nameController = TextEditingController();
  final contactController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool usePhone = false;
  bool acceptedTerms = false;
  bool submitting = false;
  String? formError;
  String language = 'English';
  String marketCode = 'ZM';
  final selectedInterests = <String>{};

  static const markets = [
    (code: 'ZM', label: 'Zambia', currency: 'ZMW'),
  ];

  static const interestOptions = [
    'Fiction',
    'Personal growth',
    'Business',
    'Culture',
    'Biography',
    'Education',
    'Faith & inspiration',
    'History',
  ];

  @override
  void dispose() {
    nameController.dispose();
    contactController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (step) {
            _Step.welcome => _WelcomeStep(
                key: const ValueKey('welcome'),
                firebaseReady: context.watch<SessionState>().firebaseAuthAvailable,
                onCreate: () => setState(() {
                  step = _Step.createAccount;
                  formError = null;
                }),
                onSignIn: () => setState(() {
                  step = _Step.signIn;
                  formError = null;
                }),
                onGuest: () {
                  context.read<SessionState>().continueAsGuest();
                  setState(() => step = _Step.market);
                },
              ),
            _Step.createAccount => _AuthForm(
                key: const ValueKey('create'),
                title: 'Join Listen+',
                subtitle: 'Save your library, follow creators, and pick up where you left off across devices.',
                formKey: formKey,
                nameController: nameController,
                contactController: contactController,
                passwordController: passwordController,
                usePhone: usePhone,
                acceptedTerms: acceptedTerms,
                showName: true,
                showTerms: true,
                showForgotPassword: false,
                submitting: submitting,
                errorText: formError,
                primaryLabel: 'Create account',
                onToggleMethod: _onToggleMethod,
                onTermsChanged: (value) => setState(() => acceptedTerms = value),
                onBack: () => setState(() {
                  step = _Step.welcome;
                  formError = null;
                }),
                onForgotPassword: null,
                onSubmit: _submitCreateAccount,
              ),
            _Step.signIn => _AuthForm(
                key: const ValueKey('signin'),
                title: 'Welcome back',
                subtitle: 'Sign in to open your library, purchases, and reading progress.',
                formKey: formKey,
                nameController: nameController,
                contactController: contactController,
                passwordController: passwordController,
                usePhone: usePhone,
                acceptedTerms: acceptedTerms,
                showName: false,
                showTerms: false,
                showForgotPassword: true,
                submitting: submitting,
                errorText: formError,
                primaryLabel: 'Sign in',
                onToggleMethod: _onToggleMethod,
                onTermsChanged: (_) {},
                onBack: () => setState(() {
                  step = _Step.welcome;
                  formError = null;
                }),
                onForgotPassword: _sendReset,
                onSubmit: _submitSignIn,
              ),
            _Step.market => _MarketStep(
                key: const ValueKey('market'),
                marketCode: marketCode,
                language: language,
                markets: markets,
                onMarketChanged: (code) => setState(() => marketCode = code),
                onLanguageChanged: (value) => setState(() => language = value),
                onContinue: () {
                  final market = markets.firstWhere((item) => item.code == marketCode);
                  final session = context.read<SessionState>();
                  session.setMarket(code: market.code, label: market.label, currency: market.currency);
                  session.setLanguage(language);
                  setState(() => step = _Step.interests);
                },
              ),
            _Step.interests => _InterestsStep(
                key: const ValueKey('interests'),
                options: interestOptions,
                selected: selectedInterests,
                onToggle: (value) {
                  setState(() {
                    if (!selectedInterests.add(value)) selectedInterests.remove(value);
                  });
                },
                onSkip: _finish,
                onContinue: _finish,
              ),
          },
        ),
      ),
    );
  }

  void _onToggleMethod(bool phone) {
    if (phone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone sign-in is coming soon. Use email for now.')),
      );
      setState(() => usePhone = false);
      return;
    }
    setState(() => usePhone = false);
  }

  Future<void> _submitCreateAccount() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (!acceptedTerms) {
      setState(() => formError = 'Please accept the Terms and Privacy Policy to continue.');
      return;
    }
    setState(() {
      submitting = true;
      formError = null;
    });
    try {
      await context.read<SessionState>().createAccountWithEmail(
            name: nameController.text,
            email: contactController.text,
            password: passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        submitting = false;
        step = _Step.market;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        formError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        formError = 'Could not create your account. Try again.';
      });
    }
  }

  Future<void> _submitSignIn() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() {
      submitting = true;
      formError = null;
    });
    try {
      await context.read<SessionState>().signInWithEmail(
            email: contactController.text,
            password: passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        submitting = false;
        step = _Step.market;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        formError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        formError = 'Could not sign in. Try again.';
      });
    }
  }

  Future<void> _sendReset() async {
    final email = contactController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => formError = 'Enter your email above, then tap Forgot password.');
      return;
    }
    setState(() {
      submitting = true;
      formError = null;
    });
    try {
      await context.read<SessionState>().sendPasswordReset(email);
      if (!mounted) return;
      setState(() => submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        formError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        formError = 'Could not send reset email. Try again.';
      });
    }
  }

  Future<void> _finish() async {
    final session = context.read<SessionState>();
    session.setInterests(selectedInterests);
    final enableNotifications = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stay in the loop?'),
        content: const Text(
          'Get optional reminders about library progress and new stories. You can change this anytime in Profile.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable')),
        ],
      ),
    );
    session.setNotificationsEnabled(enableNotifications == true);
    session.completeOnboarding();
    session.showNotice(
      session.isGuest
          ? 'Browsing as guest. Sign in anytime from Profile.'
          : 'Welcome to Listen+, ${session.displayName}.',
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    super.key,
    required this.firebaseReady,
    required this.onCreate,
    required this.onSignIn,
    required this.onGuest,
  });

  final bool firebaseReady;
  final VoidCallback onCreate;
  final VoidCallback onSignIn;
  final VoidCallback onGuest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            'listen+',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ListenColors.leaf,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'A world of stories',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 14),
          Text(
            'Discover, buy, read and listen — starting in Zambia. Creators can publish and earn through Studio.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.45, color: ListenColors.ink.withValues(alpha: 0.7)),
          ),
          const Spacer(),
          FilledButton(onPressed: onCreate, child: const Text('Create account')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onSignIn, child: const Text('Sign in')),
          const SizedBox(height: 8),
          TextButton(onPressed: onGuest, child: const Text('Continue as guest')),
          const SizedBox(height: 8),
          Text(
            firebaseReady
                ? 'Purchases stay in demo mode until the Listen+ API is live.'
                : 'Signing in is warming up — you can browse as a guest in the meantime.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: ListenColors.ink.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    super.key,
    required this.title,
    required this.subtitle,
    required this.formKey,
    required this.nameController,
    required this.contactController,
    required this.passwordController,
    required this.usePhone,
    required this.acceptedTerms,
    required this.showName,
    required this.showTerms,
    required this.showForgotPassword,
    required this.submitting,
    required this.errorText,
    required this.primaryLabel,
    required this.onToggleMethod,
    required this.onTermsChanged,
    required this.onBack,
    required this.onForgotPassword,
    required this.onSubmit,
  });

  final String title;
  final String subtitle;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController contactController;
  final TextEditingController passwordController;
  final bool usePhone;
  final bool acceptedTerms;
  final bool showName;
  final bool showTerms;
  final bool showForgotPassword;
  final bool submitting;
  final String? errorText;
  final String primaryLabel;
  final ValueChanged<bool> onToggleMethod;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onBack;
  final VoidCallback? onForgotPassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: submitting ? null : onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.65))),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Email')),
              ButtonSegment(value: true, label: Text('Phone')),
            ],
            selected: {usePhone},
            onSelectionChanged: submitting ? null : (value) => onToggleMethod(value.first),
          ),
          const SizedBox(height: 16),
          if (showName) ...[
            TextFormField(
              controller: nameController,
              enabled: !submitting,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: contactController,
            enabled: !submitting,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Enter an email address';
              if (!value.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: passwordController,
            enabled: !submitting,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: showName ? 'At least 8 characters, with a letter and a number' : null,
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              final password = value ?? '';
              if (password.isEmpty) return 'Enter a password';
              if (!showName) return null;
              if (password.length < 8) return 'Use at least 8 characters';
              final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
              final hasNumber = RegExp(r'[0-9]').hasMatch(password);
              if (!hasLetter || !hasNumber) {
                return 'Include at least one letter and one number';
              }
              return null;
            },
          ),
          if (showForgotPassword) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: submitting ? null : onForgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
          ],
          if (showTerms) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: acceptedTerms,
              onChanged: submitting ? null : (value) => onTermsChanged(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I accept the Terms of Service and Privacy Policy'),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: submitting ? null : () => openLegalDoc(context, LegalDoc.terms),
                  child: const Text('Terms'),
                ),
                TextButton(
                  onPressed: submitting ? null : () => openLegalDoc(context, LegalDoc.privacy),
                  child: const Text('Privacy'),
                ),
              ],
            ),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 8),
            Text(errorText!, style: const TextStyle(color: Colors.redAccent, height: 1.35)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(primaryLabel),
          ),
        ],
      ),
    );
  }
}

class _MarketStep extends StatelessWidget {
  const _MarketStep({
    super.key,
    required this.marketCode,
    required this.language,
    required this.markets,
    required this.onMarketChanged,
    required this.onLanguageChanged,
    required this.onContinue,
  });

  final String marketCode;
  final String language;
  final List<({String code, String label, String currency})> markets;
  final ValueChanged<String> onMarketChanged;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your market & language', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Prices and payment methods depend on your selected market. You can change this later in Profile.',
            style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: marketCode,
            decoration: const InputDecoration(labelText: 'Country / market', border: OutlineInputBorder()),
            items: [
              for (final market in markets)
                DropdownMenuItem(
                  value: market.code,
                  child: Text('${market.label} · ${market.currency}'),
                ),
            ],
            onChanged: (value) {
              if (value != null) onMarketChanged(value);
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: language,
            decoration: const InputDecoration(labelText: 'Preferred language', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'English', child: Text('English')),
              DropdownMenuItem(value: 'Bemba', child: Text('Bemba')),
              DropdownMenuItem(value: 'Nyanja', child: Text('Nyanja')),
            ],
            onChanged: (value) {
              if (value != null) onLanguageChanged(value);
            },
          ),
          const Spacer(),
          FilledButton(onPressed: onContinue, child: const Text('Continue')),
        ],
      ),
    );
  }
}

class _InterestsStep extends StatelessWidget {
  const _InterestsStep({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onSkip,
    required this.onContinue,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What do you love to explore?', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Optional. Helps shape discovery. You can edit this later.',
            style: TextStyle(height: 1.4, color: ListenColors.ink.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(
                    option,
                    style: TextStyle(
                      color: selected.contains(option) ? Colors.white : ListenColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: selected.contains(option),
                  showCheckmark: false,
                  selectedColor: ListenColors.leaf,
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: selected.contains(option)
                        ? ListenColors.leaf
                        : ListenColors.ink.withValues(alpha: 0.22),
                  ),
                  onSelected: (_) => onToggle(option),
                ),
            ],
          ),
          const Spacer(),
          FilledButton(onPressed: onContinue, child: const Text('Start exploring')),
          TextButton(onPressed: onSkip, child: const Text('Skip for now')),
        ],
      ),
    );
  }
}
