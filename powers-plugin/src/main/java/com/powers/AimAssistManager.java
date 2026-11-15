package com.powers;

import org.bukkit.GameMode;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.entity.ArmorStand;
import org.bukkit.entity.Entity;
import org.bukkit.entity.LivingEntity;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.util.Vector;

import java.util.Locale;
import java.util.Set;

/**
 * Aim assist: while the trigger is active, gently turns the player's view
 * toward the nearest target inside a cone in front of them. The server
 * sets the rotation, so it works on unmodified clients.
 *
 * Triggers (config "aim-assist.trigger"):
 *   ranged - while drawing a bow, charging a crossbow or readying a trident
 *   sneak  - while sneaking
 *   always - whenever aim assist is on
 */
final class AimAssistManager {
    private static final Set<Material> RANGED = Set.of(Material.BOW, Material.CROSSBOW, Material.TRIDENT);

    private final PowersPlugin plugin;
    private final PowerManager powers;

    AimAssistManager(PowersPlugin plugin, PowerManager powers) {
        this.plugin = plugin;
        this.powers = powers;
    }

    /** Runs every server tick. */
    void tick() {
        for (Player player : plugin.getServer().getOnlinePlayers()) {
            if (!powers.isOn(player, Power.AIM_ASSIST) || player.getGameMode() == GameMode.SPECTATOR) {
                continue;
            }
            if (!triggerActive(player)) {
                continue;
            }
            LivingEntity target = findTarget(player);
            if (target != null) {
                turnToward(player, aimPoint(target), powers.aimStrength(player) / 10f);
            }
        }
    }

    private boolean triggerActive(Player player) {
        String trigger = plugin.getConfig().getString("aim-assist.trigger", "ranged").toLowerCase(Locale.ROOT);
        return switch (trigger) {
            case "always" -> true;
            case "sneak" -> player.isSneaking();
            default -> {
                ItemStack active = player.getActiveItem();
                yield player.isHandRaised() && RANGED.contains(active.getType());
            }
        };
    }

    private LivingEntity findTarget(Player player) {
        double range = plugin.getConfig().getDouble("aim-assist.range", 48);
        double maxAngle = Math.toRadians(plugin.getConfig().getDouble("aim-assist.fov", 30));
        boolean targetMobs = plugin.getConfig().getBoolean("aim-assist.target-mobs", false);

        Location eye = player.getEyeLocation();
        Vector facing = eye.getDirection();
        LivingEntity best = null;
        double bestAngle = maxAngle;

        for (Entity entity : player.getNearbyEntities(range, range, range)) {
            if (!(entity instanceof LivingEntity living) || living.isDead() || entity instanceof ArmorStand) {
                continue;
            }
            if (entity instanceof Player other) {
                if (other.getGameMode() == GameMode.SPECTATOR) {
                    continue;
                }
            } else if (!targetMobs) {
                continue;
            }

            Vector toTarget = aimPoint(living).toVector().subtract(eye.toVector());
            if (toTarget.lengthSquared() > range * range || toTarget.lengthSquared() < 1e-6) {
                continue;
            }
            double angle = facing.angle(toTarget);
            if (angle < bestAngle && player.hasLineOfSight(living)) {
                best = living;
                bestAngle = angle;
            }
        }
        return best;
    }

    /** Aim a little below the eyes (upper chest), which suits both melee and arrows. */
    private static Location aimPoint(LivingEntity target) {
        return target.getEyeLocation().subtract(0, 0.25, 0);
    }

    private static void turnToward(Player player, Location point, float strength) {
        Location eye = player.getEyeLocation();
        double dx = point.getX() - eye.getX();
        double dy = point.getY() - eye.getY();
        double dz = point.getZ() - eye.getZ();

        float targetYaw = (float) Math.toDegrees(Math.atan2(-dx, dz));
        float targetPitch = (float) Math.toDegrees(-Math.atan2(dy, Math.sqrt(dx * dx + dz * dz)));

        float yaw = eye.getYaw() + wrap(targetYaw - eye.getYaw()) * strength;
        float pitch = eye.getPitch() + (targetPitch - eye.getPitch()) * strength;
        player.setRotation(yaw, pitch);
    }

    /** Wraps an angle difference into -180..180 so it turns the short way. */
    private static float wrap(float degrees) {
        return ((degrees % 360) + 540) % 360 - 180;
    }
}
