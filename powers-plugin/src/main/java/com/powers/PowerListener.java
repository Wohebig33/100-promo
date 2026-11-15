package com.powers;

import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerChangedWorldEvent;
import org.bukkit.event.player.PlayerGameModeChangeEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerRespawnEvent;
import org.bukkit.event.player.PlayerSwapHandItemsEvent;

/** Keeps powers consistent across quits, respawns, world and game mode changes. */
public final class PowerListener implements Listener {
    private final PowersPlugin plugin;
    private final PowerManager powers;
    private final Menus menus;

    public PowerListener(PowersPlugin plugin, PowerManager powers, Menus menus) {
        this.plugin = plugin;
        this.powers = powers;
        this.menus = menus;
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        // Puts their game mode, walk speed and flight back to normal.
        powers.disableAll(event.getPlayer());
    }

    /** Sneak + swap-hands key (F by default) opens the menu. */
    @EventHandler(ignoreCancelled = true)
    public void onSwapHands(PlayerSwapHandItemsEvent event) {
        Player player = event.getPlayer();
        if (plugin.getConfig().getBoolean("menu-shortcut", true)
                && player.isSneaking()
                && player.hasPermission("powers.menu")) {
            event.setCancelled(true);
            menus.openMain(player);
        }
    }

    @EventHandler(priority = EventPriority.MONITOR, ignoreCancelled = true)
    public void onGameModeChange(PlayerGameModeChangeEvent event) {
        powers.onGameModeChange(event.getPlayer(), event.getNewGameMode());
    }

    @EventHandler
    public void onRespawn(PlayerRespawnEvent event) {
        Player player = event.getPlayer();
        plugin.getServer().getScheduler().runTask(plugin, () -> powers.reapply(player));
    }

    @EventHandler
    public void onWorldChange(PlayerChangedWorldEvent event) {
        Player player = event.getPlayer();
        plugin.getServer().getScheduler().runTask(plugin, () -> powers.reapply(player));
    }
}
