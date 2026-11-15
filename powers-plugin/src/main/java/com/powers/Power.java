package com.powers;

/** The toggleable powers, with their display name and permission. */
public enum Power {
    FLY("Fly", "powers.fly"),
    SPEED("Speed boost", "powers.speed"),
    NOCLIP("Noclip", "powers.noclip"),
    TRACKER("Tracker", "powers.tracker");

    private final String displayName;
    private final String permission;

    Power(String displayName, String permission) {
        this.displayName = displayName;
        this.permission = permission;
    }

    public String displayName() {
        return displayName;
    }

    public String permission() {
        return permission;
    }
}
