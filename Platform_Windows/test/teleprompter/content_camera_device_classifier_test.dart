import 'package:autoteleprompter/features/teleprompter/services/content_camera_device_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies native laptop cameras without treating them as external USB',
      () {
    const raw = r'ASUS FHD webcam <\\?\usb#vid_2b7e&pid_c711&mi_00#camera>';

    expect(ContentCameraDeviceClassifier.isNativeName(raw), isTrue);
    expect(ContentCameraDeviceClassifier.isExternalUsbName(raw), isFalse);
    expect(
      ContentCameraDeviceClassifier.sourceTypeLabel(raw),
      'Native camera',
    );
  });

  test('classifies external USB cameras separately from native cameras', () {
    const raw = r'Logitech HD Webcam C920 <\\?\usb#vid_046d&pid_082d>';

    expect(ContentCameraDeviceClassifier.isNativeName(raw), isFalse);
    expect(ContentCameraDeviceClassifier.isExternalUsbName(raw), isTrue);
    expect(
      ContentCameraDeviceClassifier.sourceTypeLabel(raw),
      'USB camera',
    );
  });

  test('classifies virtual bridge cameras for NDI OBS and phone feeds', () {
    expect(
      ContentCameraDeviceClassifier.isVirtualName('OBS Virtual Camera'),
      isTrue,
    );
    expect(
      ContentCameraDeviceClassifier.isVirtualName('NDI HX Camera'),
      isTrue,
    );
    expect(
      ContentCameraDeviceClassifier.isVirtualName('OpenLightform Phone Feed'),
      isTrue,
    );
    expect(
      ContentCameraDeviceClassifier.isVirtualName('DroidCam Source 3'),
      isTrue,
    );
    expect(
      ContentCameraDeviceClassifier.isVirtualName('Iriun Webcam'),
      isTrue,
    );
    expect(
      ContentCameraDeviceClassifier.isVirtualName('Camo Camera'),
      isTrue,
    );
  });

  test('ignores IR and depth sensors for native and USB buckets', () {
    const ir = 'Integrated Camera IR';
    const depth = 'Intel RealSense Depth Camera';

    expect(ContentCameraDeviceClassifier.isNativeName(ir), isFalse);
    expect(ContentCameraDeviceClassifier.isExternalUsbName(ir), isFalse);
    expect(ContentCameraDeviceClassifier.isNativeName(depth), isFalse);
    expect(ContentCameraDeviceClassifier.isExternalUsbName(depth), isFalse);
  });

  test('friendly names remove raw Windows device paths', () {
    const raw = r'ASUS FHD webcam <\\?\usb#vid_2b7e&pid_c711&mi_00#camera>';

    expect(
      ContentCameraDeviceClassifier.friendlyName(raw),
      'ASUS FHD webcam',
    );
  });
}
