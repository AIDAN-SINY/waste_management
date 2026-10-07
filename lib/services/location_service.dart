import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'; // Required for address lookup
import 'package:latlong2/latlong.dart'; // Required for OSM compatibility

class LocationService {
  // 1. Get current GPS Position and convert to OSM LatLng format
  Future<LatLng> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled on this device.';
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permissions are denied.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Location permissions are permanently denied. Please enable them in settings.';
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // We return the LatLng object used by flutter_map (Leaflet)
    return LatLng(position.latitude, position.longitude);
  }

  // 2. PROFESSIONAL FEATURE: Convert Coordinates to Neighborhood Name
  // This satisfies the manager's requirement to "use libraries" for addresses.
  Future<String> getNeighborhoodName(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        // Logical priority for Cameroon: Neighborhood (subLocality) -> District (locality)
        String neighborhood = place.subLocality ?? "";
        String city = place.locality ?? "";

        if (neighborhood.isEmpty) return city;
        return "$neighborhood, $city";
      }
      return "Unknown Neighborhood";
    } catch (e) {
      return "Coordinate Point ($lat, $lng)";
    }
  }
}
