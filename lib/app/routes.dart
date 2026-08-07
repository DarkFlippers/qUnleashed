import '../components/navigation.dart';
import '../pages/about/page.dart';
import '../pages/archive/map/page.dart';
import '../pages/flibler/page.dart';
import '../pages/flibler/project/page.dart';
import '../pages/flibler/settings_page.dart';
import '../pages/option/page.dart';
import '../pages/tools/paint/editor/page.dart';
import '../pages/tools/plotter/page.dart';
import '../pages/tools/remote/desktop/page.dart';

/// Binds every cross-feature route to the page that implements it. This is the
/// only place that knows about all feature pages at once.
void registerAppRoutes() {
  registerRoute(AppRoute.remoteControl, (_, _) => const RemoteControlPage());
  registerRoute(AppRoute.pixelEditor, (_, args) {
    final editor = args as PixelEditorArgs;
    return PaintPage(remotePath: editor.remotePath, client: editor.client);
  });
  registerRoute(AppRoute.plotter, (_, args) {
    final plot = args as PlotterArgs?;
    return PulsePlotterPage(initialBytes: plot?.bytes, initialName: plot?.name);
  });
  registerRoute(AppRoute.archiveMap, (_, _) => const FlipperMapPage());
  registerRoute(AppRoute.fliblerProject, (_, _) => const FliblerProjectPage());
  registerRoute(AppRoute.appSettings, (_, _) => const SettingsPage());
  registerRoute(AppRoute.about, (_, _) => const AboutPage());
  registerRoute(
    AppRoute.assemblerConsole,
    (_, _) => const AssemblerConsolePage(),
  );
  registerRoute(
    AppRoute.assemblerSettings,
    (_, _) => const AssemblerSettingsPage(),
  );
}
