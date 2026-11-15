package com.powers;

import net.kyori.adventure.bossbar.BossBar;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.NamespacedKey;
import org.bukkit.entity.Player;
import org.bukkit.persistence.PersistentDataContainer;
import org.bukkit.persistence.PersistentDataType;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Turns powers on and off, applies their effects, keeps each player's
 * fly speed / speed multiplier (saved on the player, so they survive
 * restarts), and draws the boss-bar HUD and tracker action bar.
 */
public final class PowerManager {
    public static final int MIN_FLY_LEVEL = 1;
    public static final int MAX_FLY_LEVEL = 10;
    public static final int DEFAULT_FLY_LEVEL = 2;

    public static final double MIN_SPEED = 1.5;
    public static final double MAX_SPEED = 5.0; // Minecraft caps walk speed at 5x normal
    public static final double SPEED_STEP = 0.5;
    public static final double DEFAULT_SPEED = 2.0;

    private static final float DEFAULT_WALK_SPEED = 0.2f;
    private static final float DEFAULT_FLY_SPEED = 0.1f;
    private static final String[] ARROWS = {"↑", "↗", "→", "↘", "↓", "↙", "←", "↖"};

    private final PowersPlugin plugin;
    private final NamespacedKey flyLevelKey;
    private final NamespacedKey speedKey;
    private final Map<UUID, State> states = new HashMap<>();
    private final Map<UUID, BossBar> bars = new HashMap<>();
    private boolean changingGameMode = false;

    private static final class State {
        final Set<Power> active = EnumSet.noneOf(Power.class);
        GameMode modeBeforeNoclip = GameMode.SURVIVAL;
    }

    public PowerManager(PowersPlugin plugin) {
        this.plugin = plugin;
        this.flyLevelKey = new NamespacedKey(plugin, "fly_level");
        this.speedKey = new NamespacedKey(plugin, "speed_multiplier");
    }

    private State state(Player player) {
        return states.computeIfAbsent(player.getUniqueId(), id -> new State());
    }

    public boolean isOn(Player player, Power power) {
        State state = states.get(player.getUniqueId());
        return state != null && state.active.contains(power);
    }

    public void toggle(Player player, Power power) {
        setEnabled(player, power, !isOn(player, power));
    }

    /** Turns a power on or off. Returns false if the player isn't allowed. */
    public boolean setEnabled(Player player, Power power, boolean on) {
        if (on && !player.hasPermission(power.permission())) {
            Messages.error(player, "You don't have " + power.displayName() + ".");
            return false;
        }
        State state = state(player);
        if (state.active.contains(power) == on) {
            return true;
        }
        if (on) {
            state.active.add(power);
        } else {
            state.active.remove(power);
        }

        switch (power) {
            case FLY -> {
                applyFly(player);
                if (on && player.getAllowFlight()) {
                    player.setFlying(true);
                }
            }
            case SPEED -> applySpeed(player);
            case NOCLIP -> applyNoclip(player, state, on);
            case TRACKER -> {
                if (!on) {
                    player.sendActionBar(Component.empty());
                }
            }
        }
        updateHud(player);
        return true;
    }

    /** Turns everything off and forgets the player (used on quit / shutdown). */
    public void disableAll(Player player) {
        for (Power power : Power.values()) {
            setEnabled(player, power, false);
        }
        states.remove(player.getUniqueId());
        BossBar bar = bars.remove(player.getUniqueId());
        if (bar != null) {
            player.hideBossBar(bar);
        }
    }

    public void disableAllOnline() {
        for (Player player : List.copyOf(plugin.getServer().getOnlinePlayers())) {
            disableAll(player);
        }
    }

    // Settings ----------------------------------------------------------------

    public int flyLevel(Player player) {
        Integer stored = player.getPersistentDataContainer().get(flyLevelKey, PersistentDataType.INTEGER);
        int level = stored == null ? DEFAULT_FLY_LEVEL : stored;
        return Math.clamp(level, MIN_FLY_LEVEL, MAX_FLY_LEVEL);
    }

    public int setFlyLevel(Player player, int level) {
        int clamped = Math.clamp(level, MIN_FLY_LEVEL, MAX_FLY_LEVEL);
        player.getPersistentDataContainer().set(flyLevelKey, PersistentDataType.INTEGER, clamped);
        applyFly(player);
        updateHud(player);
        return clamped;
    }

    public double speedMultiplier(Player player) {
        PersistentDataContainer data = player.getPersistentDataContainer();
        Double stored = data.get(speedKey, PersistentDataType.DOUBLE);
        return snapSpeed(stored == null ? DEFAULT_SPEED : stored);
    }

    public double setSpeedMultiplier(Player player, double multiplier) {
        double snapped = snapSpeed(multiplier);
        player.getPersistentDataContainer().set(speedKey, PersistentDataType.DOUBLE, snapped);
        applySpeed(player);
        updateHud(player);
        return snapped;
    }

    private static double snapSpeed(double value) {
        double snapped = Math.round(value / SPEED_STEP) * SPEED_STEP;
        return Math.clamp(snapped, MIN_SPEED, MAX_SPEED);
    }

    // Applying effects ----------------------------------------------------------

    private void applyFly(Player player) {
        boolean on = isOn(player, Power.FLY);
        if (isOn(player, Power.NOCLIP)) {
            return; // spectator mode handles flying while noclip is on
        }
        if (on) {
            player.setAllowFlight(true);
            player.setFlySpeed(flyLevel(player) / 10f);
        } else {
            player.setFlySpeed(DEFAULT_FLY_SPEED);
            GameMode mode = player.getGameMode();
            if (mode == GameMode.SURVIVAL || mode == GameMode.ADVENTURE) {
                player.setFlying(false);
                player.setAllowFlight(false);
            }
        }
    }

    private void applySpeed(Player player) {
        if (isOn(player, Power.SPEED)) {
            player.setWalkSpeed((float) Math.min(1.0, DEFAULT_WALK_SPEED * speedMultiplier(player)));
        } else {
            player.setWalkSpeed(DEFAULT_WALK_SPEED);
        }
    }

    private void applyNoclip(Player player, State state, boolean on) {
        changingGameMode = true;
        try {
            if (on) {
                if (player.getGameMode() != GameMode.SPECTATOR) {
                    state.modeBeforeNoclip = player.getGameMode();
                }
                player.setGameMode(GameMode.SPECTATOR);
            } else if (player.getGameMode() == GameMode.SPECTATOR) {
                player.setGameMode(state.modeBeforeNoclip);
            }
        } finally {
            changingGameMode = false;
        }
        if (!on) {
            applyFly(player); // changing game mode resets flight
        }
    }

    /** Called when something else changes the player's game mode. */
    public void onGameModeChange(Player player, GameMode newMode) {
        if (changingGameMode) {
            return;
        }
        State state = states.get(player.getUniqueId());
        if (state == null) {
            return;
        }
        if (state.active.contains(Power.NOCLIP) && newMode != GameMode.SPECTATOR) {
            state.active.remove(Power.NOCLIP); // they left spectator some other way
            updateHud(player);
        }
        // Game mode changes reset flight; put it back next tick.
        plugin.getServer().getScheduler().runTask(plugin, () -> reapply(player));
    }

    /** Re-applies effects that the game can reset (respawn, world change, game mode change). */
    public void reapply(Player player) {
        if (!player.isOnline()) {
            return;
        }
        applyFly(player);
        applySpeed(player);
    }

    // HUD -----------------------------------------------------------------------

    public void updateHud(Player player) {
        List<Component> parts = new ArrayList<>();
        for (Power power : Power.values()) {
            if (!isOn(player, power)) {
                continue;
            }
            String text = switch (power) {
                case FLY -> "Fly " + flyLevel(player);
                case SPEED -> "Speed x" + Messages.number(speedMultiplier(player));
                default -> power.displayName();
            };
            parts.add(Component.text(text, NamedTextColor.GREEN));
        }

        BossBar bar = bars.get(player.getUniqueId());
        if (parts.isEmpty()) {
            if (bar != null) {
                player.hideBossBar(bar);
            }
            return;
        }

        Component title = Component.join(
                net.kyori.adventure.text.JoinConfiguration.separator(Component.text("  ·  ", NamedTextColor.DARK_GRAY)),
                parts);
        if (bar == null) {
            bar = BossBar.bossBar(title, 1f, BossBar.Color.GREEN, BossBar.Overlay.PROGRESS);
            bars.put(player.getUniqueId(), bar);
        } else {
            bar.name(title);
        }
        player.showBossBar(bar);
    }

    // Tracker -------------------------------------------------------------------

    public void startTasks() {
        plugin.getServer().getScheduler().runTaskTimer(plugin, this::updateTrackers, 20L, 10L);
    }

    private void updateTrackers() {
        double range = plugin.getConfig().getDouble("tracker-range", 2000);
        for (Player viewer : plugin.getServer().getOnlinePlayers()) {
            if (isOn(viewer, Power.TRACKER)) {
                viewer.sendActionBar(trackerLine(viewer, range));
            }
        }
    }

    private Component trackerLine(Player viewer, double range) {
        Location from = viewer.getLocation();
        double rangeSquared = range * range;

        List<Player> nearby = new ArrayList<>();
        for (Player other : viewer.getWorld().getPlayers()) {
            if (other != viewer && other.getLocation().distanceSquared(from) <= rangeSquared) {
                nearby.add(other);
            }
        }
        if (nearby.isEmpty()) {
            return Component.text("No players nearby", NamedTextColor.GRAY);
        }
        nearby.sort(Comparator.comparingDouble(p -> p.getLocation().distanceSquared(from)));

        List<Component> parts = new ArrayList<>();
        for (Player other : nearby.subList(0, Math.min(3, nearby.size()))) {
            Location to = other.getLocation();
            int distance = (int) Math.round(to.distance(from));
            parts.add(Component.text(other.getName() + " ", NamedTextColor.YELLOW)
                    .append(Component.text(distance + "m " + arrow(from, to), NamedTextColor.WHITE)));
        }
        return Component.join(
                net.kyori.adventure.text.JoinConfiguration.separator(Component.text("   |   ", NamedTextColor.DARK_GRAY)),
                parts);
    }

    /** Arrow pointing toward {@code to}, relative to where {@code from} is facing. */
    private static String arrow(Location from, Location to) {
        double dx = to.getX() - from.getX();
        double dz = to.getZ() - from.getZ();
        // Minecraft yaw: 0 = south (+Z), 90 = west (-X); it grows turning right.
        double targetYaw = Math.toDegrees(Math.atan2(-dx, dz));
        double relative = targetYaw - from.getYaw();
        relative = ((relative % 360) + 540) % 360 - 180; // -180..180, positive = to the right
        int index = Math.floorMod((int) Math.round(relative / 45.0), 8);
        return ARROWS[index];
    }
}
