// Sovereign Control — boreas + prometheus front-end as a Quick Settings tile.
// Lives in the same dropdown as Wi-Fi / Bluetooth / Night Light.
// All actual hardware control happens in the system daemons over D-Bus;
// this extension is purely a UI facade.

import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import {Extension, gettext as _} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';

const BOREAS_IFACE = `
<node>
    <interface name="org.jesternet.Boreas">
        <method name="SetFanProfile">
            <arg type="s" direction="in"  name="profile"/>
            <arg type="s" direction="out" name="result"/>
        </method>
        <method name="GetCurrentProfile">
            <arg type="s" direction="out" name="profile"/>
        </method>
        <method name="GetStatusDescription">
            <arg type="s" direction="out" name="description"/>
        </method>
        <method name="GetBackendInfo">
            <arg type="s" direction="out" name="info"/>
        </method>
    </interface>
</node>`;

const PROMETHEUS_IFACE = `
<node>
    <interface name="org.jesternet.Prometheus">
        <method name="SetPerformanceProfile">
            <arg type="s" direction="in"  name="profile"/>
            <arg type="s" direction="out" name="result"/>
        </method>
        <method name="GetCurrentProfile">
            <arg type="s" direction="out" name="profile"/>
        </method>
    </interface>
</node>`;

function titleCase(s) {
    if (!s) return s;
    return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

const SovereignToggle = GObject.registerClass(
class SovereignToggle extends QuickSettings.QuickMenuToggle {
    _init(boreasProxy, prometheusProxy) {
        super._init({
            title: _('Fan & CPU'),
            subtitle: _('Auto'),
            iconName: 'weather-clear-symbolic',
            toggleMode: false,
        });
        this._boreasProxy = boreasProxy;
        this._prometheusProxy = prometheusProxy;

        this.menu.setHeader(
            'weather-clear-symbolic',
            _('Fan & CPU'),
            _('Thermal & Performance')
        );

        // ─── Thermal Control (Boreas) ───
        this._addHeader(_('⚡ THERMAL CONTROL'));
        this._addFanItem(_('Silent Fans'),    'silent');
        this._addFanItem(_('Balanced Fans'),  'balanced');
        this._addFanItem(_('MAX POWER Fans'), 'maxpower');
        this._addFanItem(_('Auto Fans'),      'auto');

        // ─── Performance Control (Prometheus) ───
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._addHeader(_('🔥 PERFORMANCE CONTROL'));
        this._addCpuItem(_('Silent CPU'),    'silent');
        this._addCpuItem(_('Balanced CPU'),  'balanced');
        this._addCpuItem(_('WARSPEED CPU'),  'warspeed');

        // ─── Combined ───
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._addHeader(_('⚔  COMBINED SOVEREIGNTY'));
        const totalWar = new PopupMenu.PopupMenuItem(_('TOTAL WAR'));
        totalWar.connect('activate', () => this._totalWar());
        this.menu.addMenuItem(totalWar);

        // Sync subtitle from daemon on creation, and whenever the menu opens.
        this._refreshFromDaemon();
        this.menu.connect('open-state-changed', (_menu, isOpen) => {
            if (isOpen) this._refreshFromDaemon();
        });
    }

    _addHeader(text) {
        const item = new PopupMenu.PopupMenuItem(text, { reactive: false, can_focus: false });
        this.menu.addMenuItem(item);
    }

    _addFanItem(label, profile) {
        const item = new PopupMenu.PopupMenuItem(label);
        item.connect('activate', () => this._setFanProfile(profile));
        this.menu.addMenuItem(item);
    }

    _addCpuItem(label, profile) {
        const item = new PopupMenu.PopupMenuItem(label);
        item.connect('activate', () => this._setCpuProfile(profile));
        this.menu.addMenuItem(item);
    }

    _setFanProfile(profile) {
        if (!this._boreasProxy) {
            Main.notify('Fan & CPU', 'Boreas daemon not connected');
            return;
        }
        this._boreasProxy.SetFanProfileRemote(profile, (result, error) => {
            if (error) {
                Main.notify('Boreas', `Error: ${error.message}`);
                return;
            }
            this.subtitle = titleCase(profile);
            // Tile glows when not on Auto (manual control engaged).
            this.checked = profile.toLowerCase() !== 'auto';
        });
    }

    _setCpuProfile(profile) {
        if (!this._prometheusProxy) {
            Main.notify('Fan & CPU', 'Prometheus daemon not connected');
            return;
        }
        this._prometheusProxy.SetPerformanceProfileRemote(profile, (result, error) => {
            if (error) Main.notify('Prometheus', `Error: ${error.message}`);
        });
    }

    _totalWar() {
        Main.notify('TOTAL WAR', 'Engaging maximum sovereignty...');
        this._setFanProfile('maxpower');
        this._setCpuProfile('warspeed');
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
            Main.notify('TOTAL WAR', 'Full sovereign performance active!');
            return GLib.SOURCE_REMOVE;
        });
    }

    _refreshFromDaemon() {
        if (!this._boreasProxy) return;
        this._boreasProxy.GetCurrentProfileRemote((result, error) => {
            if (!error && result && result[0]) {
                this.subtitle = titleCase(result[0]);
                this.checked = result[0].toLowerCase() !== 'auto';
            }
        });
    }
});

const SovereignIndicator = GObject.registerClass(
class SovereignIndicator extends QuickSettings.SystemIndicator {
    _init(boreasProxy, prometheusProxy) {
        super._init();
        this._toggle = new SovereignToggle(boreasProxy, prometheusProxy);
        this.quickSettingsItems.push(this._toggle);
    }
});

export default class SovereignExtension extends Extension {
    enable() {
        const BoreasProxy     = Gio.DBusProxy.makeProxyWrapper(BOREAS_IFACE);
        const PrometheusProxy = Gio.DBusProxy.makeProxyWrapper(PROMETHEUS_IFACE);

        try {
            this._boreasProxy = new BoreasProxy(
                Gio.DBus.system,
                'org.jesternet.Boreas',
                '/org/jesternet/Boreas'
            );
        } catch (e) {
            logError(e, 'Failed to connect to Boreas daemon');
        }
        try {
            this._prometheusProxy = new PrometheusProxy(
                Gio.DBus.system,
                'org.jesternet.Prometheus',
                '/org/jesternet/Prometheus'
            );
        } catch (e) {
            logError(e, 'Failed to connect to Prometheus daemon');
        }

        this._indicator = new SovereignIndicator(this._boreasProxy, this._prometheusProxy);
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.quickSettingsItems.forEach(item => item.destroy());
        this._indicator?.destroy();
        this._indicator = null;
        this._boreasProxy = null;
        this._prometheusProxy = null;
    }
}
