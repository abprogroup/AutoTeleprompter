class ContentCameraDeviceClassifier {
  const ContentCameraDeviceClassifier._();

  static bool isIntegratedName(String rawName) {
    final name = rawName.toLowerCase();
    return name.contains('integrated') ||
        name.contains('built-in') ||
        name.contains('builtin') ||
        name.contains('internal') ||
        name.contains('facetime') ||
        name.contains('isight') ||
        name.contains('macbook') ||
        name.contains('imac') ||
        name.contains('studio display') ||
        name.contains('apple camera') ||
        name.contains('continuity camera') ||
        name.contains('asus fhd') ||
        name.contains('asus hd');
  }

  static bool isIrOrDepthName(String rawName) {
    final name = rawName.toLowerCase();
    return name.contains(' ir ') ||
        name.startsWith('ir ') ||
        name.endsWith(' ir') ||
        name.contains('infrared') ||
        name.contains('depth');
  }

  static bool isUsbName(String rawName) {
    final name = rawName.toLowerCase();
    return name.contains('usb') ||
        name.contains('uvc') ||
        name.contains('external') ||
        name.contains('logitech') ||
        name.contains('elgato') ||
        name.contains('razer kiyo') ||
        name.contains('brio');
  }

  static bool isVirtualName(String rawName) {
    final name = rawName.toLowerCase();
    return name.contains('ndi') ||
        name.contains('obs') ||
        name.contains('virtual') ||
        name.contains('droidcam') ||
        name.contains('iriun') ||
        name.contains('epoccam') ||
        name.contains('camo') ||
        name.contains('snap camera') ||
        name.contains('ip camera') ||
        name.contains('lightform') ||
        name.contains('screen capture');
  }

  static bool isNativeName(String rawName) {
    return !isVirtualName(rawName) &&
        !isIrOrDepthName(rawName) &&
        isIntegratedName(rawName);
  }

  static bool isNativeCandidate(
    String rawName, {
    required bool isFrontFacing,
    required bool isMacOS,
  }) {
    if (isVirtualName(rawName) || isIrOrDepthName(rawName)) return false;
    if (isIntegratedName(rawName)) return true;
    return isMacOS && isFrontFacing && !isUsbName(rawName);
  }

  static bool isExternalUsbName(String rawName) {
    return !isVirtualName(rawName) &&
        !isIrOrDepthName(rawName) &&
        !isIntegratedName(rawName) &&
        isUsbName(rawName);
  }

  static String sourceTypeLabel(String rawName) {
    if (isVirtualName(rawName)) return 'Virtual / NDI / OBS camera';
    if (isIrOrDepthName(rawName)) return 'IR / depth camera';
    if (isNativeName(rawName)) return 'Native camera';
    if (isExternalUsbName(rawName) || isUsbName(rawName)) return 'USB camera';
    return 'Camera';
  }

  static String friendlyName(String rawName, {String fallback = 'Camera'}) {
    var name = rawName.trim();
    final pathMarker = name.indexOf(' <');
    if (pathMarker > 0) name = name.substring(0, pathMarker).trim();
    final slashMarker = name.indexOf(r'\\?\');
    if (slashMarker > 0) name = name.substring(0, slashMarker).trim();
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name.isEmpty ? fallback : name;
  }
}
