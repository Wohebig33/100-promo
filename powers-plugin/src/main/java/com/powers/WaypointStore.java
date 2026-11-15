package com.powers;

import org.bukkit.Location;
import org.bukkit.NamespacedKey;
import org.bukkit.World;
import org.bukkit.entity.Player;
import org.bukkit.persistence.PersistentDataType;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Each player's personal waypoints, stored on the player itself (saved
 * with their player data, so no extra files and they survive restarts).
 */
public final class WaypointStore {
    public static final Pattern VALID_NAME = Pattern.compile("[A-Za-z0-9_-]{1,24}");

    private final PowersPlugin plugin;
    private final NamespacedKey key;

    public record Waypoint(String name, UUID worldId, double x, double y, double z, float yaw, float pitch) {
        /** The location, or null if the world isn't loaded. */
        public Location toLocation() {
            World world = org.bukkit.Bukkit.getWorld(worldId);
            return world == null ? null : new Location(world, x, y, z, yaw, pitch);
        }

        String serialize() {
            return String.join(";", name, worldId.toString(), Double.toString(x), Double.toString(y),
                    Double.toString(z), Float.toString(yaw), Float.toString(pitch));
        }

        static Waypoint parse(String line) {
            String[] f = line.split(";");
            if (f.length != 7) {
                return null;
            }
            try {
                return new Waypoint(f[0], UUID.fromString(f[1]), Double.parseDouble(f[2]), Double.parseDouble(f[3]),
                        Double.parseDouble(f[4]), Float.parseFloat(f[5]), Float.parseFloat(f[6]));
            } catch (IllegalArgumentException e) {
                return null;
            }
        }
    }

    public enum AddResult { ADDED, REPLACED, INVALID_NAME, FULL }

    public WaypointStore(PowersPlugin plugin) {
        this.plugin = plugin;
        this.key = new NamespacedKey(plugin, "waypoints");
    }

    public int max() {
        return Math.max(1, plugin.getConfig().getInt("max-waypoints", 45));
    }

    public List<Waypoint> list(Player player) {
        String raw = player.getPersistentDataContainer().get(key, PersistentDataType.STRING);
        List<Waypoint> result = new ArrayList<>();
        if (raw == null || raw.isEmpty()) {
            return result;
        }
        for (String line : raw.split("\n")) {
            Waypoint waypoint = Waypoint.parse(line);
            if (waypoint != null) {
                result.add(waypoint);
            }
        }
        return result;
    }

    private void save(Player player, List<Waypoint> waypoints) {
        List<String> lines = new ArrayList<>();
        for (Waypoint waypoint : waypoints) {
            lines.add(waypoint.serialize());
        }
        player.getPersistentDataContainer().set(key, PersistentDataType.STRING, String.join("\n", lines));
    }

    public Optional<Waypoint> find(Player player, String name) {
        for (Waypoint waypoint : list(player)) {
            if (waypoint.name().equalsIgnoreCase(name)) {
                return Optional.of(waypoint);
            }
        }
        return Optional.empty();
    }

    /** Saves a waypoint at the location; an existing one with the same name is replaced. */
    public AddResult add(Player player, String name, Location location) {
        if (!VALID_NAME.matcher(name).matches()) {
            return AddResult.INVALID_NAME;
        }
        List<Waypoint> waypoints = list(player);
        boolean replaced = waypoints.removeIf(w -> w.name().equalsIgnoreCase(name));
        if (!replaced && waypoints.size() >= max()) {
            return AddResult.FULL;
        }
        waypoints.add(new Waypoint(name, location.getWorld().getUID(), location.getX(), location.getY(),
                location.getZ(), location.getYaw(), location.getPitch()));
        save(player, waypoints);
        return replaced ? AddResult.REPLACED : AddResult.ADDED;
    }

    public boolean remove(Player player, String name) {
        List<Waypoint> waypoints = list(player);
        boolean removed = waypoints.removeIf(w -> w.name().equalsIgnoreCase(name));
        if (removed) {
            save(player, waypoints);
        }
        return removed;
    }

    /** "Waypoint-1", "Waypoint-2", ... whichever isn't taken yet. */
    public String nextDefaultName(Player player) {
        List<String> taken = new ArrayList<>();
        for (Waypoint waypoint : list(player)) {
            taken.add(waypoint.name().toLowerCase(Locale.ROOT));
        }
        int n = 1;
        while (taken.contains(("waypoint-" + n))) {
            n++;
        }
        return "Waypoint-" + n;
    }
}
