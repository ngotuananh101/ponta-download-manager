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

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
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
