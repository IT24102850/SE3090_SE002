import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/ui/ui.dart';

/// Brand hue and glyph per network. Identity is never colour alone: the
/// glyph and the platform name always travel with it.
({Color color, IconData icon}) platformStyle(String platform) {
  switch (platform) {
    case 'Facebook':
      return (color: const Color(0xFF4C8DF6), icon: Icons.facebook);
    case 'Instagram':
      return (color: const Color(0xFFE1306C), icon: Icons.camera_alt_outlined);
    case 'TikTok':
      return (color: AppColors.cyan, icon: Icons.music_note_outlined);
    default:
      return (color: AppColors.textMuted, icon: Icons.public);
  }
}

class PlatformMark extends StatelessWidget {
  final String platform;
  final double size;
  const PlatformMark({super.key, required this.platform, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final style = platformStyle(platform);
    return Tooltip(
      message: platform,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(size / 3.2),
          border: Border.all(color: style.color.withValues(alpha: .55)),
        ),
        child: Icon(style.icon, size: size * .52, color: style.color, semanticLabel: platform),
      ),
    );
  }
}

/// "3 min ago", "in 2 h", "5 Mar".
String relativeTime(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final ref = now ?? DateTime.now();
  final diff = t.difference(ref);
  final past = diff.isNegative;
  final abs = diff.abs();
  String unit;
  if (abs.inSeconds < 60) return past ? 'just now' : 'in under a minute';
  if (abs.inMinutes < 60) {
    unit = '${abs.inMinutes} min';
  } else if (abs.inHours < 24) {
    unit = '${abs.inHours} h';
  } else if (abs.inDays < 7) {
    unit = '${abs.inDays} d';
  } else {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]}';
  }
  return past ? '$unit ago' : 'in $unit';
}

String dateTimeLabel(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]}, $hh:$mm';
}

Future<void> copyToClipboard(BuildContext context, String text, [String done = 'Copied.']) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AppSnackBar.success(context, done);
}

Future<void> openExternal(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) AppSnackBar.error(context, 'Could not open the link.');
}

Future<bool> confirmAction(BuildContext context,
    {required String title, required String message, required String confirm, bool destructive = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.overlaySurface,
      title: Text(title, style: AppTextStyles.title),
      content: Text(message, style: AppTextStyles.body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm, style: TextStyle(color: destructive ? AppColors.error : AppColors.cyan)),
        ),
      ],
    ),
  );
  return result == true;
}

/// A tinted note — used for "reply window closed", setup hints and API warnings.
class SocialNotice extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const SocialNotice(this.text, {super.key, this.color = AppColors.warning, this.icon = Icons.info_outline});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.caption.copyWith(color: AppColors.textBody))),
        ],
      ),
    );
  }
}
