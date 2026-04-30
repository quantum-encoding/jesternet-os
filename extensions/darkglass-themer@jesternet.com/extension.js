// DarkGlass Themer — front-end for tuning blur-my-shell's "applications"
// blur profile via panel sliders.
//
// Two bugs fixed vs the original:
//   1. Schema loading. blur-my-shell's schemas live in its extension-local
//      schemas/ dir, not in any system GSettings search path, so the bare
//      `new Gio.Settings({schema: ...})` raised "schema not found". Now we
//      walk the known install dirs and load the compiled schema from the
//      one that exists, then construct Gio.Settings with that explicit
//      schema object.
//   2. Signal cleanup. Slider/menu-item callbacks captured `this` and the
//      sibling label widgets. When the indicator was destroyed, GJS GC
//      tried to invoke those callbacks during the sweep phase against
//      already-freed actors, producing "Object X already disposed"
//      warnings. We now track every connection and disconnect them all
//      in destroy() before the parent tears down child actors.

import GObject from 'gi://GObject';
import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Slider} from 'resource:///org/gnome/shell/ui/slider.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BLUR_UUID      = 'blur-my-shell@aunetx';
const BLUR_SCHEMA_ID = 'org.gnome.shell.extensions.blur-my-shell.applications';

/// Locate blur-my-shell's compiled schemas directory and return a Gio.Settings
/// bound to the .applications sub-schema. Returns null if blur-my-shell isn't
/// installed (or its schemas haven't been compiled).
function loadBlurMyShellSettings() {
    const candidates = [
        GLib.build_filenamev([GLib.get_user_data_dir(), 'gnome-shell', 'extensions', BLUR_UUID, 'schemas']),
        `/usr/share/gnome-shell/extensions/${BLUR_UUID}/schemas`,
        `/usr/local/share/gnome-shell/extensions/${BLUR_UUID}/schemas`,
    ];
    for (const dir of candidates) {
        const compiled = GLib.build_filenamev([dir, 'gschemas.compiled']);
        if (!GLib.file_test(compiled, GLib.FileTest.EXISTS)) continue;
        try {
            const source = Gio.SettingsSchemaSource.new_from_directory(
                dir,
                Gio.SettingsSchemaSource.get_default(),
                false,
            );
            const schema = source.lookup(BLUR_SCHEMA_ID, true);
            if (schema) return new Gio.Settings({settings_schema: schema});
        } catch (_) {
            // Try the next candidate.
        }
    }
    return null;
}

const DarkGlassIndicator = GObject.registerClass(
class DarkGlassIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'DarkGlass Themer', false);

        // Every signal we connect goes here so destroy() can disconnect
        // before the parent class tears the actors down.
        this._signalIds = [];

        let icon = new St.Icon({
            icon_name: 'preferences-color-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(icon);

        this._settings = loadBlurMyShellSettings();
        if (!this._settings) {
            this._buildMissingSchemaMenu();
            return;
        }

        this._buildMenu();
    }

    /// Tracked variant of GObject.connect — pushes the connection into
    /// _signalIds so destroy() can clean it up.
    _connect(obj, signal, callback) {
        const id = obj.connect(signal, callback);
        this._signalIds.push({obj, id});
        return id;
    }

    _buildMissingSchemaMenu() {
        const warn = new PopupMenu.PopupMenuItem(
            '⚠ blur-my-shell schemas not found',
            {reactive: false, can_focus: false}
        );
        this.menu.addMenuItem(warn);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addMenuItem(new PopupMenu.PopupMenuItem(
            'Install blur-my-shell, then restart the shell.',
            {reactive: false, can_focus: false}
        ));
    }

    _buildMenu() {
        let header = new PopupMenu.PopupMenuItem('🎨 DarkGlass Theme Editor', {
            reactive: false, can_focus: false
        });
        header.label.style = 'font-weight: bold;';
        this.menu.addMenuItem(header);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._addSlider('Blur Intensity', 0, 100,
            this._settings.get_int('sigma'),
            (value) => {
                this._settings.set_int('sigma', value);
                Main.notify('DarkGlass', `Blur: ${value}`);
            }
        );

        this._addSlider('Transparency', 0, 255,
            this._settings.get_int('opacity'),
            (value) => {
                this._settings.set_int('opacity', value);
                Main.notify('DarkGlass', `Transparency: ${value}`);
            }
        );

        this._addSlider('Brightness', 0, 100,
            Math.round(this._settings.get_double('brightness') * 100),
            (value) => {
                this._settings.set_double('brightness', value / 100);
                Main.notify('DarkGlass', `Brightness: ${value}%`);
            }
        );

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        let presetsHeader = new PopupMenu.PopupMenuItem('⚡ Quick Presets', {
            reactive: false, can_focus: false
        });
        presetsHeader.label.style = 'font-weight: bold;';
        this.menu.addMenuItem(presetsHeader);

        this._addPreset('Subtle Glass',         {sigma: 20, opacity: 200, brightness: 0.7});
        this._addPreset('Dark Glass (Default)', {sigma: 30, opacity: 150, brightness: 0.6});
        this._addPreset('Deep Glass',           {sigma: 40, opacity: 100, brightness: 0.5});
        this._addPreset('Crystal Clear',        {sigma: 50, opacity: 80,  brightness: 0.4});

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._addButton('💾 Export Theme Config', () => this._exportTheme());
        this._addButton('🔄 Reset to Default',    () => this._resetToDefault());
    }

    _addSlider(label, _min, max, initial, callback) {
        let item = new PopupMenu.PopupBaseMenuItem({activate: false});

        let box = new St.BoxLayout({
            vertical: false,
            x_expand: true,
            style: 'spacing: 12px;'
        });

        let labelWidget = new St.Label({
            text: label,
            style: 'min-width: 120px;'
        });
        box.add_child(labelWidget);

        let slider = new Slider(initial / max);
        slider.set_width(150);

        let valueLabel = new St.Label({
            text: initial.toString(),
            style: 'min-width: 40px; text-align: right;'
        });
        box.add_child(valueLabel);

        this._connect(slider, 'notify::value', () => {
            let value = Math.round(slider.value * max);
            valueLabel.set_text(value.toString());
            callback(value);
        });

        box.add_child(slider);
        item.add_child(box);
        this.menu.addMenuItem(item);
    }

    _addPreset(name, config) {
        let item = new PopupMenu.PopupMenuItem(`  ${name}`);
        this._connect(item, 'activate', () => {
            this._settings.set_int('sigma',         config.sigma);
            this._settings.set_int('opacity',       config.opacity);
            this._settings.set_double('brightness', config.brightness);
            Main.notify('DarkGlass', `✓ Applied: ${name}`);
        });
        this.menu.addMenuItem(item);
    }

    _addButton(label, callback) {
        let item = new PopupMenu.PopupMenuItem(label);
        this._connect(item, 'activate', callback);
        this.menu.addMenuItem(item);
    }

    _exportTheme() {
        let sigma      = this._settings.get_int('sigma');
        let opacity    = this._settings.get_int('opacity');
        let brightness = this._settings.get_double('brightness');

        Main.notify('DarkGlass',
            `Current Config:\nBlur: ${sigma}\nOpacity: ${opacity}\nBrightness: ${Math.round(brightness * 100)}%`
        );
    }

    _resetToDefault() {
        this._settings.set_int('sigma',         30);
        this._settings.set_int('opacity',       150);
        this._settings.set_double('brightness', 0.6);
        Main.notify('DarkGlass', '✓ Reset to DarkGlass defaults');
    }

    destroy() {
        // Disconnect all tracked signals BEFORE super.destroy() tears down
        // the actors. Otherwise queued callbacks fire against freed widgets
        // during the GJS GC sweep phase ("Object X already disposed" warns).
        for (const {obj, id} of this._signalIds) {
            try { obj.disconnect(id); } catch (_) {}
        }
        this._signalIds = [];
        this._settings = null;
        super.destroy();
    }
});

export default class DarkGlassThemerExtension extends Extension {
    enable() {
        this._indicator = new DarkGlassIndicator();
        Main.panel.addToStatusArea('darkglass-themer', this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
