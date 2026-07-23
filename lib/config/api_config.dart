abstract final class ApiConfig {
  static const String backendBaseUrl = 'https://debloat-production.up.railway.app';

  // The Auralay backend lives in [AuralayDevFlags.apiBaseUrl] — the Eyes +
  // Game tabs and every Realtime/villain/presence service read from that
  // single source. Preserved verbatim from Auralay so the live Railway
  // deployment (auralayai-production-65c2.up.railway.app) keeps serving
  // every grafted endpoint without re-config. Build-time overrideable via
  //   --dart-define=AURALAY_API=https://other-url.up.railway.app
  // for hitting a staging deployment from a TestFlight build.
}
