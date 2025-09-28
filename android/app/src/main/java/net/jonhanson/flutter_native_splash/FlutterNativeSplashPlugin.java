package net.jonhanson.flutter_native_splash;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * A minimal no-op plugin implementation to satisfy builds where flutter_native_splash
 * is only used as a dev dependency. The actual plugin functionality is not required
 * at runtime because the splash screen assets are generated at build time.
 */
public class FlutterNativeSplashPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    // No-op. The flutter_native_splash package does not need runtime behavior.
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    // No-op.
  }
}
