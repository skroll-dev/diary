import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';

class ProfileAvatarButton extends ConsumerWidget {
  const ProfileAvatarButton({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authServiceProvider).when(
          data: (user) {
            if (user.isAnonymous) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => context.push('/profile'),
              child: _Avatar(photoUrl: user.photoURL, size: size),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.size});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.primaryContainer,
      backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
      child: photoUrl == null
          ? Icon(
              Icons.person_rounded,
              size: size * 0.55,
              color: cs.onPrimaryContainer,
            )
          : null,
    );
  }
}
