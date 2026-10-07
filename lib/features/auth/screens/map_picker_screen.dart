import 'package:flutter/material.dart';
import 'package:waste_pro/core/brand.dart';
import 'package:flutter_map/flutter_map.dart'; // The Leaflet for Flutter
import 'package:latlong2/latlong.dart'; // Coordinates
import 'package:geocoding/geocoding.dart'; // Neighborhood lookup
import 'package:geolocator/geolocator.dart'; // GPS "locate me"
import 'package:google_fonts/google_fonts.dart';

/// Full-screen OSM map where the client pins their collection point.
///
/// Returns `{'location': LatLng, 'address': String}` via [Navigator.pop]
/// when the user confirms.
///
/// - The map opens on Cameroon and cannot be moved outside it.
/// - [initialLocation] centers the map on the client's already-saved point
///   (profile "Collection Point") instead.
/// - The crosshair button grabs the device GPS ("Use my current location").
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initialLocation});

  /// Position initiale (point déjà enregistré) ; sinon tout le Cameroun.
  final LatLng? initialLocation;

  /// Cameroon's bounding box (the map stays inside it).
  static final cameroon = LatLngBounds(
    const LatLng(1.65, 8.45),
    const LatLng(13.10, 16.20),
  );

  /// Geographic centre of Cameroon.
  static const cameroonCenter = LatLng(5.7, 12.35);

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late LatLng _currentCenter =
      widget.initialLocation ?? MapPickerScreen.cameroonCenter;
  String _address = "Zoom in and move the map to your gate";

  /// True once a point is identified (confirm is enabled).
  late bool _hasPlace = widget.initialLocation != null;

  /// True when [_address] is a real neighbourhood / street name (not just
  /// coordinates — reverse geocoding is unavailable in some browsers).
  bool _named = false;
  final MapController _mapController = MapController();
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Automatic location pin: when no saved point exists, grab the device
    // GPS on open so the pin starts at (or near) the client's real door.
    // With a saved point the map is already centered there — no need.
    if (widget.initialLocation == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
    }
  }

  Future<void> _getAddress(LatLng point) async {
    setState(() {
      _address = "Locating neighborhood..."; // Visual feedback
      _hasPlace = false;
    });
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(point.latitude, point.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          // Professional Fallback Logic:
          // Try Neighborhood -> if empty try Street -> if empty try City
          _address = place.subLocality?.isNotEmpty == true
              ? place.subLocality!
              : (place.thoroughfare?.isNotEmpty == true
                  ? place.thoroughfare!
                  : place.locality ?? "Unknown Area");
          _hasPlace = true;
          _named = _address != "Unknown Area";
        });
      }
    } catch (e) {
      debugPrint("GEO ERROR: $e");
      // No neighbourhood name (e.g. in a browser): the point is kept, the
      // client types the neighbourhood name in the form.
      setState(() {
        _address = "Point set (${point.latitude.toStringAsFixed(4)}, "
            "${point.longitude.toStringAsFixed(4)})";
        _hasPlace = true;
        _named = false;
      });
    }
  }

  /// Grabs the device GPS and centers the map on it.
  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _address = "Location permission denied — move the map manually";
        });
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final point = LatLng(position.latitude, position.longitude);
      if (!MapPickerScreen.cameroon.contains(point)) {
        if (!mounted) return;
        setState(() => _address =
            "You seem to be outside Cameroon — move the map to your gate");
        return;
      }
      _mapController.move(point, 17);
      setState(() {
        _currentCenter = point;
        _address = "Locating neighborhood...";
      });
      await _getAddress(point);
    } catch (e) {
      debugPrint("GPS ERROR: $e");
      if (mounted) {
        setState(() => _address = "Could not get GPS position — move the map manually");
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Set Collection Point",
          style: GoogleFonts.poppins(fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // THE OPENSTREETMAP LAYER
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              // Saved point: street level; otherwise the whole country.
              initialZoom: widget.initialLocation != null ? 17 : 6,
              minZoom: 5,
              // The centre (= the pin) cannot leave Cameroon. (`contain`
              // would fail when the whole country fits on a wide screen.)
              cameraConstraint: CameraConstraint.containCenter(
                bounds: MapPickerScreen.cameroon,
              ),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.center != null) {
                  _currentCenter = position.center!;
                  _getAddress(_currentCenter);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.waste_pro',
              ),
            ],
          ),

          // STATIC CENTER PIN
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40), // Adjust for pin tip
              child: Icon(Icons.location_on, color: Colors.red, size: 50),
            ),
          ),

          // GPS "locate me" button (right side, above the address card)
          Positioned(
            right: 20,
            bottom: 130,
            child: FloatingActionButton.small(
              heroTag: 'mapPickerLocate',
              onPressed: _useMyLocation,
              backgroundColor: Colors.white,
              foregroundColor: Brand.green,
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),

          // TOP ADDRESS CARD
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: Text(
                _address,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // CONFIRM BUTTON
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Brand.green,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: _hasPlace
                  ? () {
                      Navigator.pop(context, {
                        'location': _currentCenter,
                        // Empty when the neighbourhood name is unknown.
                        'address': _named ? _address : '',
                      });
                    }
                  : null,
              child: const Text(
                "CONFIRM THIS POINT",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
