import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Sélecteur de photo réutilisable (pick depuis la galerie ou la caméra,
/// option de coller une URL d'image directement).
///
/// Utilisé par la pré-inscription client (photo de maison/rue pour
/// repérer l'adresse) et par les formulaires du backoffice
/// (photo de profil client / collecteur).
class PhotoPickerField extends StatefulWidget {
  const PhotoPickerField({
    super.key,
    this.label,
    this.initialValue = '',
    this.onChanged,
    this.accentColor = const Color(0xFF0B5A2A),
    this.mutedColor = const Color(0xFF6E8274),
    this.borderColor = const Color(0xFFE1E9DD),
    this.fillColor = Colors.white,
  });

  final String? label;

  /// URL http(s) ou chemin de fichier local déjà enregistré.
  final String initialValue;

  /// Appelé à chaque changement (URL saisie ou fichier local pické).
  final ValueChanged<String>? onChanged;

  final Color accentColor;
  final Color mutedColor;
  final Color borderColor;
  final Color fillColor;

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  late final TextEditingController _urlCtrl =
      TextEditingController(text: widget.initialValue);
  String _localPath = '';

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    // Declaring android.permission.CAMERA in the manifest without requesting
    // it at runtime makes Android silently block the camera intent and
    // image_picker fall back to the gallery — so always request first.
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isPermanentlyDenied
                  ? 'Camera permission is blocked. Enable it in Settings → Apps → WastePro → Permissions.'
                  : 'Camera permission is required to take a photo.',
            ),
            action: status.isPermanentlyDenied
                ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
                : null,
          ),
        );
        return;
      }
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() => _localPath = picked.path);
      widget.onChanged?.call(picked.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo picker unavailable: $error')),
      );
    }
  }

  void _useUrl(String value) {
    setState(() => _localPath = '');
    widget.onChanged?.call(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final current = _localPath.isNotEmpty ? _localPath : widget.initialValue;
    final isFile = current.isNotEmpty && !current.startsWith('http');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: widget.mutedColor,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Aperçu
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: widget.fillColor,
                border: Border.all(color: widget.borderColor),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: current.isEmpty
                  ? Icon(Icons.image_outlined,
                      size: 22, color: widget.mutedColor)
                  // Image.file is unsupported on Flutter web (no dart:io);
                  // picked paths there are blob: URLs that Image.network renders.
                  : isFile && !kIsWeb
                      ? Image.file(File(current), fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              size: 22,
                              color: widget.mutedColor))
                      : Image.network(current, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                              Icons.broken_image_outlined,
                              size: 22,
                              color: widget.mutedColor)),
            ),
            const SizedBox(width: 10),
            // Boutons pick
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pickButton(
                        icon: Icons.photo_camera_outlined,
                        label: 'Camera',
                        onTap: () => _pick(ImageSource.camera),
                      ),
                      const SizedBox(width: 8),
                      _pickButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        onTap: () => _pick(ImageSource.gallery),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Ou coller une URL directement
                  TextField(
                    controller: _urlCtrl,
                    onChanged: _useUrl,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '…or paste an image URL',
                      hintStyle:
                          TextStyle(fontSize: 11.5, color: widget.mutedColor),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: widget.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: widget.accentColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pickButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.accentColor.withValues(alpha: 0.08),
          border: Border.all(color: widget.accentColor.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: widget.accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
