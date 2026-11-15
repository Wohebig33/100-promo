package com.powers;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import net.kyori.adventure.text.format.TextDecoration;
import org.bukkit.Color;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.entity.Display;
import org.bukkit.entity.Player;
import org.bukkit.entity.TextDisplay;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * ESP: floating name / health / distance labels above other players that
 * show through walls. Each label is a text display that only the player
 * using ESP can see, so nobody else notices anything.
 *
 * Labels only reach players within the server's entity tracking range for
 * display entities, so very far players won't have one (use the tracker).
 */
final class EspManager {
    private final PowersPlugin plugin;
    private final PowerManager powers;
    /** viewer -> (target -> that viewer's label for the target) */
    private final Map<UUID, Map<UUID, TextDisplay>> labels = new HashMap<>();
    private int ticks;

    EspManager(PowersPlugin plugin, PowerManager powers) {
        this.plugin = plugin;
        this.powers = powers;
    }

    /** Runs every 2 server ticks. */
    void tick() {
        ticks++;
        boolean refreshText = ticks % 5 == 0; // text every 10 ticks, position every 2
        double range = plugin.getConfig().getDouble("esp.range", 96);
        double rangeSquared = range * range;

        for (Player viewer : plugin.getServer().getOnlinePlayers()) {
            if (!powers.isOn(viewer, Power.ESP)) {
                continue;
            }
            Map<UUID, TextDisplay> mine = labels.computeIfAbsent(viewer.getUniqueId(), id -> new HashMap<>());
            Set<UUID> seen = new HashSet<>();
            Location viewerLocation = viewer.getLocation();

            for (Player target : viewer.getWorld().getPlayers()) {
                if (target == viewer || target.getGameMode() == GameMode.SPECTATOR) {
                    continue;
                }
                if (target.getLocation().distanceSquared(viewerLocation) > rangeSquared) {
                    continue;
                }
                seen.add(target.getUniqueId());

                Location spot = target.getLocation().add(0, target.getHeight() + 0.6, 0);
                TextDisplay label = mine.get(target.getUniqueId());
                if (label == null || !label.isValid() || label.getWorld() != target.getWorld()) {
                    if (label != null) {
                        label.remove();
                    }
                    label = spawnLabel(viewer, spot);
                    mine.put(target.getUniqueId(), label);
                    label.text(text(viewer, target));
                } else {
                    label.teleport(spot);
                    if (refreshText) {
                        label.text(text(viewer, target));
                    }
                }
            }

            // Remove labels for players who left, died into another world or went out of range.
            mine.entrySet().removeIf(entry -> {
                if (!seen.contains(entry.getKey())) {
                    entry.getValue().remove();
                    return true;
                }
                return false;
            });
        }
    }

    private TextDisplay spawnLabel(Player viewer, Location spot) {
        TextDisplay label = spot.getWorld().spawn(spot, TextDisplay.class, display -> {
            display.setVisibleByDefault(false); // hidden from everyone...
            display.setPersistent(false); // ...and never saved with the world
            display.setBillboard(Display.Billboard.CENTER);
            display.setSeeThrough(true); // visible through blocks
            display.setShadowed(true);
            display.setDefaultBackground(false);
            display.setBackgroundColor(Color.fromARGB(96, 0, 0, 0));
            display.setTeleportDuration(2); // glide between position updates
            display.setViewRange(4f);
        });
        viewer.showEntity(plugin, label); // ...except the ESP user
        return label;
    }

    private static Component text(Player viewer, Player target) {
        int distance = (int) Math.round(target.getLocation().distance(viewer.getLocation()));
        int health = (int) Math.ceil(target.getHealth());
        return Component.text(target.getName(), NamedTextColor.RED).decorate(TextDecoration.BOLD)
                .append(Component.newline())
                .append(Component.text(health + " HP  ·  " + distance + "m", NamedTextColor.WHITE)
                        .decoration(TextDecoration.BOLD, false));
    }

    /** Removes every label this viewer can see. */
    void clear(Player viewer) {
        Map<UUID, TextDisplay> mine = labels.remove(viewer.getUniqueId());
        if (mine != null) {
            mine.values().forEach(TextDisplay::remove);
        }
    }

    void removeAll() {
        for (Map<UUID, TextDisplay> mine : labels.values()) {
            mine.values().forEach(TextDisplay::remove);
        }
        labels.clear();
    }
}
