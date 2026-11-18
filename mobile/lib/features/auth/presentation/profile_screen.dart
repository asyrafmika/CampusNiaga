import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/widgets/unread_badge.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../data/auth_repository.dart';
import 'auth_controller.dart';

/// Account / Profile: who is signed in, shortcuts, and sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const Key signOutKey = Key('profile-sign-out');
  static const Key businessKey = Key('profile-business');
  static const Key ordersKey = Key('profile-orders');
  static const Key discoverKey = Key('profile-discover');
  static const Key messagesKey = Key('profile-messages');
  static const Key paymentDetailsKey = Key('profile-payment-details');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(myNameProvider).value ?? '';
    final email = ref.watch(userAccessProvider).value?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0x33FFFFFF),
                  child: Text(
                    name.isEmpty ? '?' : name.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(color: Color(0xD9FFFFFF)),
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Verified USM student',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _Section(
            children: [
              _Item(
                icon: Icons.inventory_2_outlined,
                title: 'My listings',
                onTap: () => context.push(AppRoutes.myListings),
              ),
              _Item(
                icon: Icons.receipt_long_outlined,
                title: 'My bookings',
                onTap: () => context.go(AppRoutes.reservations),
              ),
              _Item(
                key: messagesKey,
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Messages',
                subtitle: 'Chats about your bookings and orders',
                badge: ref.watch(unreadChatsProvider).value ?? 0,
                onTap: () => context.push(AppRoutes.messages),
              ),
              _Item(
                key: discoverKey,
                icon: Icons.lightbulb_outline_rounded,
                title: 'Discover',
                subtitle: 'Request products and see possible opportunities',
                onTap: () => context.push(AppRoutes.discover),
              ),
              _Item(
                key: ordersKey,
                icon: Icons.shopping_bag_outlined,
                title: 'My orders',
                subtitle: 'Orders and pre-orders from student businesses',
                onTap: () => context.push(AppRoutes.orders),
              ),
              _Item(
                icon: Icons.add_circle_outline_rounded,
                title: 'Sell an item',
                onTap: () => context.push(AppRoutes.sell),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            children: [
              _Item(
                key: businessKey,
                icon: Icons.storefront_outlined,
                title: 'My business',
                subtitle: 'Apply, track your application or see your business',
                onTap: () => context.push(AppRoutes.business),
              ),
              _Item(
                key: paymentDetailsKey,
                icon: Icons.account_balance_outlined,
                title: 'Payment details',
                subtitle:
                    'Bank account or QR code for buyers who pay by '
                    'transfer',
                onTap: () => context.push(AppRoutes.paymentDetails),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Section(
            children: [
              _Item(
                icon: Icons.handshake_outlined,
                title: 'How trading works',
                subtitle:
                    'Buyers pay cash on pickup, or by bank transfer or QR with '
                    'a receipt the seller checks. CampusNiaga never holds the '
                    'money and doesn’t deliver.',
              ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            key: signOutKey,
            onPressed: ref.read(authControllerProvider.notifier).signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Column(children: children),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Unread count shown before the chevron; hidden when 0.
  final int badge;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: AppColors.primary),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: onTap == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge > 0) UnreadBadge(count: badge),
              const Icon(Icons.chevron_right_rounded, color: AppColors.icon),
            ],
          ),
  );
}
