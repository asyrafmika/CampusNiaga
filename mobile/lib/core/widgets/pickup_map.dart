import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/geo_point.dart';
import '../theme/app_colors.dart';
import 'state_views.dart';

/// Map tiles come from OpenStreetMap over the network. Widget tests turn
/// them off (they have no network); everything else still renders.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// Opens a pin in the phone's maps app for directions. Returns `false` when
/// nothing could open it. Replaced in tests.
final openDirectionsProvider = Provider<Future<bool> Function(GeoPoint)>(
  (ref) => (point) async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${point.latitude},${point.longitude}',
    });
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  },
);

const String _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

// OpenStreetMap's tile policy asks apps to identify themselves.
const String _userAgentPackage = 'com.asyrafmika.campusniaga';

const double _pinSize = 44;

LatLng _latLng(GeoPoint p) => LatLng(p.latitude, p.longitude);

/// The tiles (unless turned off) and the attribution OpenStreetMap requires.
List<Widget> _baseLayers(WidgetRef ref) => [
  if (ref.watch(mapTilesEnabledProvider))
    TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgentPackage),
  const _Attribution(),
];

/// The credit OpenStreetMap's licence requires. Its own widget, unlike
/// flutter_map's, shrinks with an ellipsis on a narrow map instead of
/// overflowing.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomRight,
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xCCFFFFFF),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '© OpenStreetMap contributors',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, color: Color(0xFF333333)),
      ),
    ),
  );
}

class _PinIcon extends StatelessWidget {
  const _PinIcon();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.location_on,
    size: _pinSize,
    color: AppColors.primary,
    shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
  );
}

MarkerLayer _markerAt(GeoPoint point) => MarkerLayer(
  markers: [
    Marker(
      point: _latLng(point),
      width: _pinSize,
      height: _pinSize,
      // The pin's tip, not its middle, marks the spot.
      alignment: Alignment.topCenter,
      child: const _PinIcon(),
    ),
  ],
);

/// A small, still map with the pin. Tapping it calls [onTap].
class PickupMapPreview extends ConsumerWidget {
  const PickupMapPreview({
    super.key,
    required this.point,
    this.height = 160,
    this.onTap,
  });

  final GeoPoint point;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          FlutterMap(
            // A new point builds a new map, centred on it.
            key: ValueKey(point),
            options: MapOptions(
              initialCenter: _latLng(point),
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [..._baseLayers(ref), _markerAt(point)],
          ),
          if (onTap != null)
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Shows [point] full screen, with directions in the phone's maps app.
Future<void> showPickupMap(
  BuildContext context, {
  required GeoPoint point,
  required String place,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => PickupMapScreen(point: point, place: place),
  ),
);

class PickupMapScreen extends ConsumerWidget {
  const PickupMapScreen({super.key, required this.point, required this.place});

  final GeoPoint point;

  /// The seller's own words for the spot, e.g. "Desasiswa Tekun lobby".
  final String place;

  static const Key directionsKey = Key('pickup-directions');

  Future<void> _directions(BuildContext context, WidgetRef ref) async {
    final opened = await ref.read(openDirectionsProvider)(point);
    if (!opened && context.mounted) {
      showMessage(context, 'No maps app could open this spot.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Pickup spot')),
    body: FlutterMap(
      options: MapOptions(
        initialCenter: _latLng(point),
        initialZoom: 17,
        minZoom: 5,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [..._baseLayers(ref), _markerAt(point)],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.place_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    place,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: directionsKey,
              onPressed: () => _directions(context, ref),
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Directions'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lets the seller drag the map under a fixed pin; returns the chosen spot,
/// or `null` when they go back.
class PickupPinPickerScreen extends ConsumerStatefulWidget {
  const PickupPinPickerScreen({super.key, this.initial});

  final GeoPoint? initial;

  static const Key confirmKey = Key('pin-confirm');

  @override
  ConsumerState<PickupPinPickerScreen> createState() =>
      _PickupPinPickerScreenState();
}

class _PickupPinPickerScreenState extends ConsumerState<PickupPinPickerScreen> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _confirm() {
    final centre = _map.camera.center;
    Navigator.of(
      context,
    ).pop(PickupPinRules.rounded(GeoPoint(centre.latitude, centre.longitude)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = widget.initial ?? UsmCampus.main.centre;
    return Scaffold(
      appBar: AppBar(title: const Text('Pin the pickup spot')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _latLng(start),
              initialZoom: 17,
              minZoom: 5,
              maxZoom: 19,
              // The centre is the pin, so it can't leave the area the
              // database accepts.
              cameraConstraint: CameraConstraint.containCenter(
                bounds: LatLngBounds(
                  const LatLng(
                    PickupPinRules.minLatitude,
                    PickupPinRules.minLongitude,
                  ),
                  const LatLng(
                    PickupPinRules.maxLatitude,
                    PickupPinRules.maxLongitude,
                  ),
                ),
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: _baseLayers(ref),
          ),
          // The fixed pin, its tip on the map's centre.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -_pinSize / 2),
                child: const _PinIcon(),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final campus in UsmCampus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        key: Key('pin-campus-${campus.name}'),
                        avatar: const Icon(Icons.school_outlined, size: 18),
                        label: Text(campus.label),
                        backgroundColor: theme.colorScheme.surface,
                        onPressed: () => _map.move(_latLng(campus.centre), 16),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Drag the map until the pin sits on the spot. Choose a public '
                'place such as a cafeteria, library or desasiswa lobby, never '
                'your room: every student who sees the item sees this pin.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: PickupPinPickerScreen.confirmKey,
                onPressed: _confirm,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Use this spot'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The optional pin in a form: add it, see it, move it or remove it.
class PickupPinField extends StatelessWidget {
  const PickupPinField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final GeoPoint? value;
  final ValueChanged<GeoPoint?> onChanged;
  final bool enabled;

  static const Key addKey = Key('pin-add');
  static const Key moveKey = Key('pin-move');
  static const Key removeKey = Key('pin-remove');

  Future<void> _pick(BuildContext context) async {
    final picked = await Navigator.of(context).push<GeoPoint>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PickupPinPickerScreen(initial: value),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final point = value;
    if (point == null) {
      return OutlinedButton.icon(
        key: addKey,
        onPressed: enabled ? () => _pick(context) : null,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Pin it on the map (optional)'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickupMapPreview(
          point: point,
          height: 140,
          onTap: enabled ? () => _pick(context) : null,
        ),
        Row(
          children: [
            TextButton.icon(
              key: moveKey,
              onPressed: enabled ? () => _pick(context) : null,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Move pin'),
            ),
            TextButton.icon(
              key: removeKey,
              onPressed: enabled ? () => onChanged(null) : null,
              icon: const Icon(Icons.location_off_outlined),
              label: const Text('Remove pin'),
            ),
          ],
        ),
      ],
    );
  }
}
