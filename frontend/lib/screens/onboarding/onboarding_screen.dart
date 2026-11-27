import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../widgets/serfix_components.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.onComplete,
    super.key,
  });

  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pages = [
    _OnboardingPageData(
      icon: Icons.ac_unit_outlined,
      eyebrow: 'NYAMAN DARI RUMAH',
      title: 'Perangkat rumah kembali prima.',
      description:
          'Pilih layanan AC dan elektronik rumah tangga, lalu atur jadwal '
          'servis yang sesuai.',
    ),
    _OnboardingPageData(
      icon: Icons.engineering_outlined,
      eyebrow: 'TEKNISI TERPILIH',
      title: 'Serahkan pada ahlinya.',
      description:
          'Lihat keahlian teknisi dan pantau proses servis dari penugasan '
          'sampai pekerjaan selesai.',
    ),
    _OnboardingPageData(
      icon: Icons.receipt_long_outlined,
      eyebrow: 'BIAYA LEBIH JELAS',
      title: 'Setujui estimasi sebelum mulai.',
      description:
          'Tinjau rincian biaya, chat teknisi, dan simpan riwayat servis '
          'serta garansi di satu tempat.',
    ),
  ];

  final _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    setState(() => _isCompleting = true);
    try {
      await widget.onComplete();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Onboarding belum tersimpan. $error'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isCompleting = false);
      }
    }
  }

  void _next() {
    if (_currentPage == _pages.length - 1) {
      _complete();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: SerfixAppBar(
          title: 'SerFix',
          subtitle: 'Layanan rumah tangga tepercaya',
          actions: [
            TextButton(
              onPressed: _isCompleting ? null : _complete,
              child: const Text('Lewati'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (index) =>
                          setState(() => _currentPage = index),
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.x4),
                          child: Column(
                            children: [
                              Container(
                                width: 184,
                                height: 184,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.secondary,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusXl,
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned(
                                      right: AppSpacing.x4,
                                      top: AppSpacing.x4,
                                      child: Icon(
                                        page.icon,
                                        size: AppSpacing.iconExtraLarge,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    Positioned(
                                      left: AppSpacing.x6,
                                      bottom: AppSpacing.x6,
                                      child: Container(
                                        width: 76,
                                        height: 76,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.14,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          page.icon,
                                          size: AppSpacing.iconExtraLarge,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x6),
                              SerfixStatusBadge(
                                label: page.eyebrow,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: AppSpacing.x3),
                              Text(
                                page.title,
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: AppSpacing.x2),
                              Text(
                                page.description,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.72),
                                    ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.x4,
                      AppSpacing.x2,
                      AppSpacing.x4,
                      AppSpacing.x4,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_pages.length, (index) {
                            final selected = index == _currentPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x1,
                              ),
                              width: selected ? AppSpacing.x8 : AppSpacing.x2,
                              height: AppSpacing.x2,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.neutral300,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusPill,
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: AppSpacing.x4),
                        SerfixPrimaryButton(
                          label: _currentPage == _pages.length - 1
                              ? 'Mulai gunakan SerFix'
                              : 'Lanjut',
                          icon: _currentPage == _pages.length - 1
                              ? Icons.arrow_forward_rounded
                              : Icons.chevron_right_rounded,
                          isLoading: _isCompleting,
                          onPressed: _isCompleting ? null : _next,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
}
