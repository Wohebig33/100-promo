package com.powers;

import org.bukkit.command.PluginCommand;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.List;

/**
 * Powers: fly, speed boost, noclip, a player tracker, ESP, aim assist and waypoints,
 * controlled from an in-game menu (/powers, or sneak + swap-hands key).
 * Everything runs on the server and is gated by permissions.
 */
public final class PowersPlugin extends JavaPlugin {
    private PowerManager powers;

    @Override
    public void onEnable() {
        saveDefaultConfig();

        powers = new PowerManager(this);
        WaypointStore waypoints = new WaypointStore(this);
        Menus menus = new Menus(this, powers, waypoints);

        PowersCommand executor = new PowersCommand(powers, waypoints, menus);
        for (String name : List.of("powers", "fly", "flyspeed", "speed", "noclip", "tracker", "esp", "aimassist",
                "waypoint")) {
            PluginCommand command = getCommand(name);
            if (command == null) {
                getLogger().severe("Command /" + name + " is missing from plugin.yml");
                continue;
            }
            command.setExecutor(executor);
            command.setTabCompleter(executor);
        }

        getServer().getPluginManager().registerEvents(new PowerListener(this, powers, menus), this);
        getServer().getPluginManager().registerEvents(menus, this);
        powers.startTasks();
    }

    @Override
    public void onDisable() {
        if (powers != null) {
            powers.disableAllOnline(); // don't leave anyone stuck in spectator or super speed
        }
    }
}
