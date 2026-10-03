import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/public_tenant_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/public_tenant_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import '../login_screen.dart';
import 'business_detail_screen.dart';
import 'customer_register_screen.dart';

class BookBusinessListScreen extends ConsumerStatefulWidget {
  const BookBusinessListScreen({super.key});

  @override
  ConsumerState<BookBusinessListScreen> createState() =>
      _BookBusinessListScreenState();
}

class _BookBusinessListScreenState
    extends ConsumerState<BookBusinessListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedType = 'All';
  bool _swipeView = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// "12 businesses", or "3 of 24" once a search or category is narrowing it.
  static String _resultSummary(int shown, int total) {
    if (shown == total) return '$total ${total == 1 ? 'business' : 'businesses'}';
    return '$shown of $total businesses';
  }

  void _onTenantTap(PublicTenant tenant) {
    final isAuthenticated = ref.read(authProvider).isAuthenticated;
    if (isAuthenticated) {
      Navigator.of(context)
          .push(slideFadeRoute(BusinessDetailScreen(tenant: tenant)));
      return;
    }
    _showSignInPrompt(tenant);
  }

  void _showSignInPrompt(PublicTenant tenant) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.overlaySurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.pill)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.magenta.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.magenta.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: AppColors.magenta, size: 28),
                ),
                const SizedBox(height: 18),
                Text(
                  'Sign in to book with ${tenant.businessName}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a free account or sign in to see availability and book instantly.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMuted.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 24),
                NeonButton(
                  label: 'Sign In',
                  height: 48,
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                ),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'Create Account',
                  height: 48,
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    final signedUp = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) =>
                              CustomerRegisterScreen(tenant: tenant)),
                    );
                    // Signed up as this tenant's customer — continue straight
                    // into their business page instead of dropping back to the list.
                    if (signedUp == true && mounted) {
                      Navigator.of(context).push(
                          slideFadeRoute(BusinessDetailScreen(tenant: tenant)));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(publicTenantsProvider);

    return AppBackgroundScaffold(
      appBar: const GlassAppBar(title: 'Find a Business'),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: NeonInputField(
                controller: _searchController,
                hintText: 'Search by business or type…',
                icon: Icons.search,
                clearable: true,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            // Type filter.
            //
            // This was a bare Material DropdownButton: it kept the framework's
            // own underline and menu colours, so it read as an unstyled control
            // dropped into a themed screen, and it hid every category behind a
            // tap. A scrolling chip strip shows what there is to choose from,
            // carries each type's own colour, and takes one tap instead of two.
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: tenantsAsync.maybeWhen(
                      data: (tenants) {
                        final types = tenants
                            .map((t) => t.businessType)
                            .where((t) => t.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort();
                        return _TypeFilterStrip(
                          types: ['All', ...types],
                          selected: _selectedType,
                          onSelected: (type) =>
                              setState(() => _selectedType = type),
                        );
                      },
                      orElse: () => const SizedBox(height: 36),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ViewModeToggle(
                    swipeView: _swipeView,
                    onChanged: (swipeView) =>
                        setState(() => _swipeView = swipeView),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tenantsAsync.when(
                loading: () => const AppLoader(),
                error: (err, stack) => ErrorState(
                  message:
                      'Could not load businesses. Check your connection and try again.',
                  onRetry: () => ref.invalidate(publicTenantsProvider),
                ),
                data: (tenants) {
                  final filtered = tenants.where((t) {
                    final matchesQuery = _query.isEmpty ||
                        t.businessName.toLowerCase().contains(_query) ||
                        t.businessType.toLowerCase().contains(_query) ||
                        (t.subType?.toLowerCase().contains(_query) ?? false);
                    final matchesType = _selectedType == 'All' ||
                        t.businessType.toLowerCase() ==
                            _selectedType.toLowerCase();
                    return matchesQuery && matchesType;
                  }).toList();

                  if (tenants.isEmpty) {
                    return const EmptyState(
                      icon: Icons.storefront_outlined,
                      title:
                          'No businesses are available for booking right now.',
                      message:
                          'Check back soon, or ask your business to register on Unify.',
                    );
                  }
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.search_off_rounded,
                      message: 'No businesses match "$_query".',
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.cyan,
                    backgroundColor: AppColors.overlaySurface,
                    onRefresh: () async =>
                        ref.invalidate(publicTenantsProvider),
                    child: _swipeView
                        ? _SwipeBusinessDeck(
                            tenants: filtered,
                            onTenantTap: _onTenantTap,
                          )
                        // A Wrap of fixed-width cards, not a GridView.
                        //
                        // A grid has to be told each cell's height up front, and
                        // every way of saying it is a guess about text: an aspect
                        // ratio made the height depend on the column width, so at
                        // two columns on a phone each card got 70px for content
                        // needing 80 and wore an overflow stripe. A fixed extent
                        // only moves the guess. Here each card is given its width
                        // and takes whatever height its own content needs, so the
                        // font, the business name and the reader's text size
                        // cannot push it out of its cell.
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              const spacing = 10.0;
                              const padding =
                                  EdgeInsets.fromLTRB(16, 6, 16, 32);
                              final columns =
                                  constraints.maxWidth > 600 ? 3 : 2;
                              final cardWidth = (constraints.maxWidth -
                                      padding.horizontal -
                                      spacing * (columns - 1)) /
                                  columns;

                              return SingleChildScrollView(
                                // Keeps pull-to-refresh working even when the list
                                // is short enough not to scroll on its own.
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: padding,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Says whether a filter is hiding
                                    // anything. Without it, a narrowed list
                                    // and a short one look identical.
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Text(
                                        _resultSummary(
                                            filtered.length, tenants.length),
                                        style: AppTextStyles.caption.copyWith(
                                            color: AppColors.textMuted),
                                      ),
                                    ),
                                    Wrap(
                                      spacing: spacing,
                                      runSpacing: spacing,
                                      children: [
                                        for (final tenant in filtered)
                                          SizedBox(
                                            width: cardWidth,
                                            child: _TenantCard(
                                              tenant: tenant,
                                              onTap: () =>
                                                  _onTenantTap(tenant),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The category chips. Each one wears its own business-type colour when
/// selected, so the filter and the cards below it speak the same visual
/// language — picking "Tourism" and seeing violet cards is one idea, not two.
class _TypeFilterStrip extends StatelessWidget {
  const _TypeFilterStrip({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<String> types;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Tall enough for the chip at the largest text size a phone offers;
      // the strip scrolls sideways rather than wrapping, so this never grows.
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = types[index];
          final isSelected = type.toLowerCase() == selected.toLowerCase();
          final accent = type == 'All'
              ? AppColors.cyan
              : BusinessTypeVisual.of(type).color;

          return GestureDetector(
            onTap: () => onSelected(type),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.18)
                    : AppColors.chromeFill,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(
                  color: isSelected
                      ? accent.withValues(alpha: 0.65)
                      : AppColors.glassBorder,
                ),
              ),
              child: Text(
                type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: isSelected ? accent : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.swipeView, required this.onChanged});

  final bool swipeView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            icon: Icons.grid_view_rounded,
            label: 'Grid view',
            selected: !swipeView,
            onPressed: () => onChanged(false),
          ),
          _ModeButton(
            icon: Icons.swipe_rounded,
            label: 'Swipe view',
            selected: swipeView,
            onPressed: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 19),
      color: selected ? AppColors.cyan : AppColors.iconSecondary,
      style: IconButton.styleFrom(
        backgroundColor:
            selected ? AppColors.cyan.withValues(alpha: 0.12) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control - 2),
        ),
      ),
    );
  }
}

class _SwipeBusinessDeck extends StatefulWidget {
  const _SwipeBusinessDeck({required this.tenants, required this.onTenantTap});

  final List<PublicTenant> tenants;
  final ValueChanged<PublicTenant> onTenantTap;

  @override
  State<_SwipeBusinessDeck> createState() => _SwipeBusinessDeckState();
}

class _SwipeBusinessDeckState extends State<_SwipeBusinessDeck> {
  int _index = 0;
  Offset _drag = Offset.zero;
  bool _animating = false;

  void _finishSwipe(double direction) {
    if (_animating || _index >= widget.tenants.length) return;
    setState(() {
      _animating = true;
      _drag = Offset(direction * 900, -20);
    });
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _index++;
        _drag = Offset.zero;
        _animating = false;
      });
    });
  }

  void _resetDeckIfNeeded() {
    if (_index > widget.tenants.length) {
      _index = widget.tenants.length;
    }
  }

  @override
  void didUpdateWidget(covariant _SwipeBusinessDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenants != widget.tenants) {
      _index = 0;
      _drag = Offset.zero;
      _animating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _resetDeckIfNeeded();
    if (_index >= widget.tenants.length) {
      return const SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(24, 30, 24, 32),
        child: EmptyState(
          icon: Icons.done_all_rounded,
          title: 'You have viewed every business',
          message:
              'Switch to grid view or change your filters to keep browsing.',
        ),
      );
    }

    final current = widget.tenants[_index];
    final next =
        _index + 1 < widget.tenants.length ? widget.tenants[_index + 1] : null;
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width - 32).clamp(280.0, 560.0);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        children: [
          Text(
            '${_index + 1} of ${widget.tenants.length}',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: cardWidth,
            height: 430,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (next != null)
                  Positioned.fill(
                    top: 12,
                    child: Transform.scale(
                      scale: 0.96,
                      child: _SwipeCard(tenant: next),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(_drag.dx, _drag.dy, 0)
                    ..rotateZ(_drag.dx / 1800),
                  child: GestureDetector(
                    onTap: () => widget.onTenantTap(current),
                    onPanUpdate: _animating
                        ? null
                        : (details) => setState(() => _drag += details.delta),
                    onPanEnd: _animating
                        ? null
                        : (_) {
                            if (_drag.dx.abs() > 90) {
                              _finishSwipe(_drag.dx.sign);
                            } else {
                              setState(() => _drag = Offset.zero);
                            }
                          },
                    child: _SwipeCard(tenant: current),
                  ),
                ),
                if (_drag.dx.abs() > 24)
                  Positioned(
                    top: 28,
                    left: _drag.dx > 0 ? 20 : null,
                    right: _drag.dx < 0 ? 20 : null,
                    child: _SwipeStamp(like: _drag.dx > 0),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Swipe right to open, left to skip',
            style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DeckAction(
                icon: Icons.close_rounded,
                label: 'Skip',
                color: AppColors.magenta,
                onPressed: () => _finishSwipe(-1),
              ),
              const SizedBox(width: 28),
              _DeckAction(
                icon: Icons.favorite_rounded,
                label: 'Open',
                color: AppColors.cyan,
                onPressed: () => _finishSwipe(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwipeCard extends StatelessWidget {
  const _SwipeCard({required this.tenant});

  final PublicTenant tenant;

  @override
  Widget build(BuildContext context) {
    final visual = BusinessTypeVisual.of(tenant.businessType);
    final imageUrl = tenant.coverImageUrl?.trim().isNotEmpty == true
        ? tenant.coverImageUrl!.trim()
        : tenant.logoUrl?.trim().isNotEmpty == true
            ? tenant.logoUrl!.trim()
            : null;

    return GlassCard(
      borderRadius: AppRadii.card,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.card),
              ),
              child: imageUrl == null
                  ? ColoredBox(
                      color: visual.color.withValues(alpha: 0.16),
                      child: Icon(visual.icon, color: visual.color, size: 72),
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => ColoredBox(
                        color: visual.color.withValues(alpha: 0.16),
                        child: Icon(visual.icon, color: visual.color, size: 72),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenant.businessName,
                  style: AppTextStyles.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Text(
                  tenant.subType?.isNotEmpty == true
                      ? '${tenant.businessType} · ${tenant.subType}'
                      : tenant.businessType,
                  style: AppTextStyles.bodyMuted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeStamp extends StatelessWidget {
  const _SwipeStamp({required this.like});

  final bool like;

  @override
  Widget build(BuildContext context) {
    final color = like ? AppColors.cyan : AppColors.magenta;
    return Transform.rotate(
      angle: like ? -0.12 : 0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          like ? 'OPEN' : 'SKIP',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _DeckAction extends StatelessWidget {
  const _DeckAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon),
          color: color,
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.14),
            side: BorderSide(color: color.withValues(alpha: 0.55)),
            padding: const EdgeInsets.all(14),
          ),
          tooltip: label,
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption.copyWith(color: color)),
      ],
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.tenant, required this.onTap});

  final PublicTenant tenant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = BusinessTypeVisual.of(tenant.businessType);

    // A tall card, not a wide row.
    //
    // The row shape was written for a full-width list and then placed two to
    // a line: at half a phone's width the name lost its tail after about
    // fifteen characters ("BrightMinds Tuiti…") and a two-part type such as
    // "Tourism · Water sports / diving" wrapped onto a second line, so cards
    // in the same run ended up different heights and the grid read as ragged.
    // Stacking the picture above the text gives the name the full card width
    // and gives every card the same shape.
    return GlassCard(
      onTap: onTap,
      borderRadius: AppRadii.row,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _TenantCover(tenant: tenant, visual: visual),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tenant.businessName,
                  style: AppTextStyles.subtitle,
                  // Two lines, because most business names need them at this
                  // width and one line turned nearly every card into an
                  // ellipsis.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _TypeTag(tenant: tenant, visual: visual),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The type pill. It carries the business hue, which is why it is built by
/// hand rather than as a shared chip.
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.tenant, required this.visual});

  final PublicTenant tenant;
  final BusinessTypeVisual visual;

  @override
  Widget build(BuildContext context) {
    final subType = tenant.subType?.trim();
    // The sub-type is the more specific, more useful half ("Water sports /
    // diving" says more than "Tourism"), and the card already shows the broad
    // type as a coloured icon over the picture. Showing one keeps the pill to
    // a single line at any width.
    final label = subType?.isNotEmpty == true ? subType! : tenant.businessType;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: visual.color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          color: visual.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The picture at the top of a card: the business's own cover where it has
/// one, and a tinted well in its type's colour where it does not — so a
/// tenant without a photo still looks deliberate rather than broken.
class _TenantCover extends StatelessWidget {
  const _TenantCover({required this.tenant, required this.visual});

  final PublicTenant tenant;
  final BusinessTypeVisual visual;

  @override
  Widget build(BuildContext context) {
    final imageUrl = tenant.coverImageUrl?.trim().isNotEmpty == true
        ? tenant.coverImageUrl!.trim()
        : tenant.logoUrl?.trim().isNotEmpty == true
            ? tenant.logoUrl!.trim()
            : null;

    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            visual.color.withValues(alpha: 0.28),
            AppColors.iconWell,
          ],
        ),
      ),
      child: Center(
        child: Icon(visual.icon,
            color: visual.color.withValues(alpha: 0.85), size: 30),
      ),
    );

    return AspectRatio(
      // Fixed ratio, so the picture never argues with the text about height.
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl == null)
            fallback
          else
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback,
            ),
          // Darkens the foot of the photo so the card's title never sits
          // against a bright sky.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x730A0E2A)],
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.overlaySurface.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                border:
                    Border.all(color: visual.color.withValues(alpha: 0.55)),
              ),
              // An icon, not text: it marks the broad type without growing
              // when the reader turns their font size up.
              child: Icon(visual.icon, color: visual.color, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
