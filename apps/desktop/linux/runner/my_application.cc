#include "my_application.h"

#include <limits.h>
#include <unistd.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Set when the app was launched with `--minimized` (auto-start at login):
  // the window stays hidden in the tray instead of being shown on first frame.
  gboolean start_minimized;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  // `--minimized` means "start in the tray": showing the window here (as the
  // template does unconditionally) made auto-start pop the full window over
  // whatever the user was doing, even though the Dart side deliberately does
  // not call show() in that case.
  if (self->start_minimized) {
    return;
  }
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// The radius Flutter rounds the window frame with (the ClipRRect in
// PdmApp) and the colour AppTheme.dark's scaffold background (#121212).
// The window has to paint the same shape underneath the Flutter view:
// see window_draw_cb. Keep the two radii in sync.
constexpr int kWindowCornerRadius = 10;
constexpr char kWindowBackground[] = "#121212";  // AppTheme.dark scaffold

// States in which the window manager fits the window to the screen. The
// corners must go square there, or they would cut into a maximized
// window. Flutter's ClipRRect still rounds, but it only reveals the
// window background underneath, which is the same app colour — so
// painting square here makes the maximized window look square.
constexpr GdkWindowState kSquareCornerStates = static_cast<GdkWindowState>(
    GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN |
    GDK_WINDOW_STATE_TILED | GDK_WINDOW_STATE_TOP_TILED |
    GDK_WINDOW_STATE_RIGHT_TILED | GDK_WINDOW_STATE_BOTTOM_TILED |
    GDK_WINDOW_STATE_LEFT_TILED);

// Paints the window's own background: a rounded rectangle in the app colour.
//
// Flutter clips its content to a 10px radius and leaves the pixels outside it
// untouched. Without this, GTK fills them with the theme's window background —
// white under Adwaita — so the window shows four bright corners instead of
// rounded ones. Marking the window app-paintable stops GTK from painting that
// background at all, and what is left unpainted here stays transparent, which
// needs the RGBA visual set up in my_application_activate. Outside a compositor
// there is no alpha to paint with, so the corners stay square.
//
// Returns FALSE so the class handler goes on to draw the child Flutter view.
static gboolean window_draw_cb(GtkWidget* widget, cairo_t* cr,
                               gpointer translucent) {
  const int width = gtk_widget_get_allocated_width(widget);
  const int height = gtk_widget_get_allocated_height(widget);

  double radius = 0;
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (GPOINTER_TO_INT(translucent) && gdk_window != nullptr &&
      (gdk_window_get_state(gdk_window) & kSquareCornerStates) == 0) {
    // GTK hands the draw handler a context already scaled for the display, so
    // the radius stays in the logical pixels Flutter drew its frame in.
    radius = kWindowCornerRadius;
  }

  GdkRGBA background;
  gdk_rgba_parse(&background, kWindowBackground);
  gdk_cairo_set_source_rgba(cr, &background);

  if (radius <= 0) {
    cairo_rectangle(cr, 0, 0, width, height);
  } else {
    const double half_pi = G_PI / 2;
    cairo_new_sub_path(cr);
    cairo_arc(cr, width - radius, radius, radius, -half_pi, 0);
    cairo_arc(cr, width - radius, height - radius, radius, 0, half_pi);
    cairo_arc(cr, radius, height - radius, radius, half_pi, 2 * half_pi);
    cairo_arc(cr, radius, radius, radius, 2 * half_pi, 3 * half_pi);
    cairo_close_path(cr);
  }
  cairo_fill(cr);

  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Always set the window title explicitly. Some desktop environments,
  // Wayland compositors, and task switchers read the window title directly.
  gtk_window_set_title(window, "Ponta Download Manager");

  // The application renders its own header bar in Flutter (AppHeader), so
  // the window carries no decoration of its own. This is done here rather
  // than from Dart: on Linux, asking nativeapi for a hidden title bar
  // switches on its custom-shadow mode, which in 0.5.10 registers an input
  // region offset from the real content area and leaves a dead band along
  // the right and bottom of the window (see the comment in `lib/main.dart`).
  // Setting it before the window is realized also means no native title
  // bar can flash before the first frame, and no GtkHeaderBar is attached.
  gtk_window_set_decorated(window, FALSE);

  // Load and set application icon from bundle assets if available.
  char exe_path[PATH_MAX];
  ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
  if (len != -1) {
    exe_path[len] = '\0';
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    const char* possible_icons[] = {
        "data/flutter_assets/assets/images/icon.png",
        "pdm.png",
        "com.ponta.pdm.png",
        nullptr
    };
    for (int i = 0; possible_icons[i] != nullptr; ++i) {
      g_autofree gchar* icon_path =
          g_build_filename(exe_dir, possible_icons[i], nullptr);
      if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
        gtk_window_set_icon_from_file(window, icon_path, nullptr);
        gtk_window_set_default_icon_from_file(icon_path, nullptr);
        break;
      }
    }
  }

  gtk_window_set_default_size(window, 950, 650);

  // Rounded corners need the window to be translucent. A GTK window without the
  // screen's RGBA visual composites over an opaque black, so the pixels Flutter
  // leaves outside its rounded frame would come out black rather than showing
  // the desktop — and `app-paintable` has nothing to paint with. The visual is
  // only there when the screen is composited; `translucent` records that and
  // window_draw_cb keeps the corners square when it is not.
  gboolean translucent = FALSE;
  GdkScreen* screen = gtk_widget_get_screen(GTK_WIDGET(window));
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
    translucent = TRUE;
  }
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  g_signal_connect(window, "draw", G_CALLBACK(window_draw_cb),
                   GINT_TO_POINTER(translucent));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // The view paints its own background before Flutter's first frame, and a
  // widget draws into the window's own surface — an opaque black here would
  // cover the rounded corners window_draw_cb paints. Transparent hands the
  // unpainted pixels back to the window, which is what makes them show the
  // desktop. Outside a compositor the corners are square anyway, so the opaque
  // default is kept there rather than leaving the gap black.
  gdk_rgba_parse(&background_color, translucent ? "#00000000" : "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // The runner is what actually shows the window (first_frame_cb), so it has
  // to know about `--minimized` itself: the Dart side setting that argument
  // aside cannot stop this callback from presenting the window.
  self->start_minimized = FALSE;
  for (char** arg = *arguments; arg != nullptr && *arg != nullptr; ++arg) {
    if (g_strcmp0(*arg, "--minimized") == 0) {
      self->start_minimized = TRUE;
      break;
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
