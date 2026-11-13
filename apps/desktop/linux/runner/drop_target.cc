#include "drop_target.h"

#include <gtk/gtk.h>

// Window-wide drag-and-drop target.
//
// GTK's drag-and-drop is asynchronous: the drop handler only says which
// representation it wants, and the payload arrives later in
// `drag-data-received`. The `dropped` event therefore leaves from
// `drag-data-received`, not from the drop handler.
//
// GTK also emits `drag-leave` right before `drag-drop` when a drag ends
// inside the widget, so the leave is deferred and cancelled by the drop.
// Without that, the UI flashes the "drag left" state on every drop.

namespace {

constexpr char kChannelName[] = "pdm/drop_target";
constexpr char kUriListAtom[] = "text/uri-list";

struct DropTarget {
  FlMethodChannel* channel = nullptr;
  // A leave waiting to be confirmed; a drop in the same turn cancels it.
  guint leave_source = 0;
  // Whether `entered` has been sent for the current drag.
  gboolean entered = FALSE;
  // True between `drag-drop` and its `drag-data-received`.
  gboolean dropping = FALSE;
};

void SendEvent(DropTarget* self, const gchar* method, FlValue* args) {
  if (self->channel == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(self->channel, method, args, nullptr,
                                  nullptr, nullptr);
}

// Splits a `text/uri-list` payload into links and local file paths.
//
// One URI per line; `#` starts a comment, and per RFC 2483 an attribute
// may follow the URI after a space. A `file://` URI is a dropped file or
// directory, which PDM does not download, so it goes into `files`;
// anything else with a scheme is a link.
void SplitUriList(const gchar* value, GPtrArray* links, GPtrArray* files) {
  g_auto(GStrv) lines = g_strsplit(value, "\n", -1);
  for (gchar** line = lines; line != nullptr && *line != nullptr; ++line) {
    g_autofree gchar* trimmed = g_strdup(g_strstrip(*line));
    if (trimmed[0] == '\0' || trimmed[0] == '#') {
      continue;
    }
    gchar* space = g_strstr_len(trimmed, -1, " ");
    if (space != nullptr) {
      *space = '\0';
    }
    if (g_str_has_prefix(trimmed, "file:")) {
      g_autofree gchar* path = g_filename_from_uri(trimmed, nullptr, nullptr);
      if (path != nullptr) {
        g_ptr_array_add(files, g_strdup(path));
      }
    } else if (g_strstr_len(trimmed, -1, ":") != nullptr) {
      g_ptr_array_add(links, g_strdup(trimmed));
    }
  }
}

void SendExited(DropTarget* self) {
  if (!self->entered) {
    return;
  }
  self->entered = FALSE;
  SendEvent(self, "exited", nullptr);
}

gboolean OnLeaveIdle(gpointer user_data) {
  auto* self = static_cast<DropTarget*>(user_data);
  self->leave_source = 0;
  SendExited(self);
  return G_SOURCE_REMOVE;
}

void CancelPendingLeave(DropTarget* self) {
  if (self->leave_source != 0) {
    g_source_remove(self->leave_source);
    self->leave_source = 0;
  }
}

// The two representations PDM understands: URI targets first (a link
// dragged out of a browser), then plain text (the same link, when the
// source has no URI form).
GtkTargetList* CreateTargetList() {
  GtkTargetList* targets = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add_uri_targets(targets, 0);
  gtk_target_list_add_text_targets(targets, 0);
  return targets;
}

gboolean OnEnter(GtkWidget* widget, GdkDragContext* context, gint, gint,
                 guint time, gpointer user_data) {
  auto* self = static_cast<DropTarget*>(user_data);
  CancelPendingLeave(self);
  // Only claim the drag when the source offers something readable, so a
  // drag that cannot be used shows the "no drop" cursor.
  g_autoptr(GtkTargetList) targets = CreateTargetList();
  if (gtk_drag_dest_find_target(widget, context, targets) == GDK_NONE) {
    gdk_drag_status(context, static_cast<GdkDragAction>(0), time);
    return FALSE;
  }
  // COPY: the app only reads the payload and must never make the source
  // believe the drag was a move (a move would delete the original file).
  gdk_drag_status(context, GDK_ACTION_COPY, time);
  if (!self->entered) {
    self->entered = TRUE;
    SendEvent(self, "entered", nullptr);
  }
  return TRUE;
}

void OnLeave(GtkWidget*, GdkDragContext*, guint, gpointer user_data) {
  auto* self = static_cast<DropTarget*>(user_data);
  CancelPendingLeave(self);
  // A timeout rather than an idle: the drop arrives in the same main-loop
  // iteration on X11, and GTK gives no ordering guarantee between the two.
  self->leave_source = g_timeout_add(50, OnLeaveIdle, self);
}

gboolean OnDrop(GtkWidget* widget, GdkDragContext* context, gint, gint,
                guint time, gpointer user_data) {
  auto* self = static_cast<DropTarget*>(user_data);
  CancelPendingLeave(self);

  g_autoptr(GtkTargetList) targets = CreateTargetList();
  const GdkAtom target = gtk_drag_dest_find_target(widget, context, targets);
  if (target == GDK_NONE) {
    SendExited(self);
    gtk_drag_finish(context, FALSE, FALSE, time);
    return TRUE;
  }
  self->dropping = TRUE;
  // gtk_drag_finish() belongs in OnDataReceived: finishing before the
  // payload arrives throws the data away.
  gtk_drag_get_data(widget, context, target, time);
  return TRUE;
}

void OnDataReceived(GtkWidget*, GdkDragContext* context, gint, gint,
                    GtkSelectionData* selection, guint, guint time,
                    gpointer user_data) {
  auto* self = static_cast<DropTarget*>(user_data);
  if (!self->dropping) {
    return;
  }
  self->dropping = FALSE;
  self->entered = FALSE;

  g_autoptr(GPtrArray) links = g_ptr_array_new_with_free_func(g_free);
  g_autoptr(GPtrArray) files = g_ptr_array_new_with_free_func(g_free);
  const guchar* raw = gtk_selection_data_get_text(selection);
  g_autofree gchar* text = nullptr;

  if (raw != nullptr) {
    // gtk_selection_data_get_text() hands back a NUL-terminated copy the
    // caller must free; g_strstrip() needs a writable string.
    gchar* value = g_strdup(reinterpret_cast<const gchar*>(raw));
    g_free(const_cast<guchar*>(raw));
    raw = nullptr;
    if (gtk_selection_data_get_target(selection) ==
        gdk_atom_intern_static_string(kUriListAtom)) {
      SplitUriList(value, links, files);
      g_free(value);
    } else {
      // Plain text: a link a browser put on the clipboard form of the drag.
      text = g_strdup(g_strstrip(value));
      g_free(value);
    }
  }

  g_autoptr(FlValue) args = fl_value_new_map();
  g_autoptr(FlValue) link_values = fl_value_new_list();
  for (guint i = 0; i < links->len; ++i) {
    fl_value_append_take(
        link_values,
        fl_value_new_string(static_cast<const gchar*>(links->pdata[i])));
  }
  g_autoptr(FlValue) file_values = fl_value_new_list();
  for (guint i = 0; i < files->len; ++i) {
    fl_value_append_take(
        file_values,
        fl_value_new_string(static_cast<const gchar*>(files->pdata[i])));
  }
  fl_value_set_string_take(args, "uris", link_values);
  fl_value_set_string_take(args, "files", file_values);
  if (text != nullptr) {
    fl_value_set_string_take(args, "text", fl_value_new_string(text));
  }

  gtk_drag_finish(context, TRUE, FALSE, time);
  SendEvent(self, "dropped", args);
}

void OnMethodCall(FlMethodChannel* /*channel*/, FlMethodCall* method_call,
                  gpointer /*user_data*/) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(fl_method_call_get_name(method_call), "isSupported") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

void DestroyDropTarget(gpointer data) {
  auto* self = static_cast<DropTarget*>(data);
  CancelPendingLeave(self);
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_clear_object(&self->channel);
  delete self;
}

}  // namespace

void drop_target_attach(FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* self = new DropTarget();
  self->channel =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, OnMethodCall,
                                            nullptr, nullptr);

  GtkWidget* widget = GTK_WIDGET(view);
  // No GTK_DEST_DEFAULT_* flags: OnEnter decides whether the drag is
  // accepted, and OnDrop asks for the payload itself.
  gtk_drag_dest_set(widget, static_cast<GtkDestDefaults>(0), nullptr, 0,
                    GDK_ACTION_COPY);
  g_autoptr(GtkTargetList) targets = CreateTargetList();
  gtk_drag_dest_set_target_list(widget, targets);

  g_signal_connect(widget, "drag-enter", G_CALLBACK(OnEnter), self);
  g_signal_connect(widget, "drag-leave", G_CALLBACK(OnLeave), self);
  g_signal_connect(widget, "drag-drop", G_CALLBACK(OnDrop), self);
  g_signal_connect(widget, "drag-data-received", G_CALLBACK(OnDataReceived),
                   self);
  g_object_set_data_full(G_OBJECT(widget), "pdm-drop-target", self,
                         DestroyDropTarget);
}
