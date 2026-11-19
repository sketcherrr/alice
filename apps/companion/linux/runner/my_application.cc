#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Native window operations stay outside the pet, memory and API layers.
static void desktop_method(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  GtkWindow* window = GTK_WINDOW(data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(name, "expanded") == 0) {
    const bool expanded = args != nullptr && fl_value_get_bool(args);
    gint x, y, old_w, old_h;
    gtk_window_get_position(window, &x, &y);
    gtk_window_get_size(window, &old_w, &old_h);
    GdkRectangle area = {0, 0, 1920, 1080};
    GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(window));
    GdkMonitor* monitor = gdk_display_get_monitor_at_window(gtk_widget_get_display(GTK_WIDGET(window)), native);
    if (monitor != nullptr) gdk_monitor_get_workarea(monitor, &area);
    const gint w = MIN(expanded ? 500 : 360, area.width);
    const gint h = MIN(expanded ? 780 : 520, area.height);
    gtk_window_resize(window, w, h);
    gtk_window_move(window, MAX(area.x, MIN(x + old_w - w, area.x + area.width - w)), MAX(area.y, MIN(y + old_h - h, area.y + area.height - h)));
    gtk_window_present(window);
  } else if (g_strcmp0(name, "drag") == 0) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkDevice* pointer = gdk_seat_get_pointer(gdk_display_get_default_seat(display));
    gint x = 0, y = 0;
    gdk_device_get_position(pointer, nullptr, &x, &y);
    gtk_window_begin_move_drag(window, 1, x, y, gtk_get_current_event_time());
  } else if (g_strcmp0(name, "onTop") == 0) {
    gtk_window_set_keep_above(window, args != nullptr && fl_value_get_bool(args));
  } else if (g_strcmp0(name, "close") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    gtk_window_close(window);
    return;
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "Alice · 小小鲸屿");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_default_size(window, 360, 520);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css, "window { background-color: transparent; box-shadow: none; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(GTK_WIDGET(window)), GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "rgba(0,0,0,0)");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)), "alice/desktop", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, desktop_method, window, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

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
