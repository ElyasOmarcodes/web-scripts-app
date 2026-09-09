import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/mac_widgets.dart';
import 'shell.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'مرسته',
            subtitle: 'څنګه کار کوي او د ستونزو حل',
          ),
          const MacGroupTitle('لومړی ګام'),
          MacGroup(
            children: [
              MacRow(
                leading: _Step(mac: mac, number: '۱'),
                title: 'نوې لارښوونه ثبت کړئ',
                subtitle: 'نوم او پیل پته ورکړئ — براوزر پرانیستل کېږي',
              ),
              MacRow(
                leading: _Step(mac: mac, number: '۲'),
                title: 'خپله لار وښایاست',
                subtitle:
                    'مینو ← تنظیمات ← ښکارېدنه ← تیاره ټم. هر کلیک او هر متن ثبتېږي.',
              ),
              MacRow(
                leading: _Step(mac: mac, number: '۳'),
                title: '«ثبتول ودروه» ووهئ',
                subtitle: 'سکریپټ خوندي شو — له اوس وروسته یوازې ▶ چلول کافي ده',
              ),
            ],
          ),
          const MacGroupTitle('ستونزې او حل'),
          MacGroup(
            children: [
              MacRow(
                leading: Icon(Icons.error_outline_rounded, size: 18, color: mac.orange),
                title: '«عنصر ونه موندل شو»',
                subtitle:
                    'سایټ بدل شوی — هغه ګام ړنګ کړئ او دا برخه بیا ثبت کړئ.',
              ),
              MacRow(
                leading: Icon(Icons.lock_outline_rounded, size: 18, color: mac.orange),
                title: 'بیا بیا پټنوم غواړي',
                subtitle:
                    'په تنظیماتو کې «ننوتنې وساته» فعال وي — یو ځل ننوځئ، بیا نه غواړي.',
              ),
              MacRow(
                leading: Icon(Icons.tab_unselected_rounded, size: 18, color: mac.orange),
                title: '«پروفایل بل ځای کې پرانیستل شوی»',
                subtitle: 'د WebScripts ټولې د براوزر کړکۍ وتړئ او بیا هڅه وکړئ.',
              ),
              MacRow(
                leading: Icon(Icons.speed_rounded, size: 18, color: mac.orange),
                title: 'ډېر ګړندی چلېږي',
                subtitle: 'په تنظیماتو کې چټکتیا 0.5× کړئ.',
              ),
            ],
          ),
          const MacGroupTitle('د پروګرام په اړه'),
          MacGroup(
            children: [
              MacRow(
                leading: Icon(Icons.info_outline_rounded, size: 18, color: mac.text2),
                title: 'WebScripts',
                subtitle: 'Python + Selenium بېک اېنډ · Flutter ظاهري ډیزاین',
                trailing: MacPill('نسخه 0.1.0'),
              ),
              MacRow(
                leading: Icon(Icons.public_rounded, size: 18, color: mac.text2),
                title: 'اوسنی براوزر',
                subtitle: state.activeBrowserName,
                trailing: MacButton(
                  label: 'تنظیمات',
                  onPressed: () => state.navigate(AppPage.settings),
                ),
              ),
              MacRow(
                leading: Icon(Icons.gavel_rounded, size: 18, color: mac.text2),
                title: 'پام',
                subtitle:
                    'دا وسیله ستاسو د خپلو حسابونو لپاره ده. د هر سایټ د کارونې '
                    'شرایط په پام کې ونیسئ — ځینې سایټونه اتومات ګرځېدنه نه مني.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.mac, required this.number});

  final MacPalette mac;
  final String number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: mac.accentSoft, shape: BoxShape.circle),
      child: Text(number,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: mac.accent)),
    );
  }
}
