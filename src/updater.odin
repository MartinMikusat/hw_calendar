package main

import "core:fmt"

UPDATER_ENABLED :: #config(HW_CALENDAR_UPDATER, false)

when UPDATER_ENABLED {
	foreign import updater_bridge "system:System.framework"
	foreign updater_bridge {
		hw_calendar_updater_initialize :: proc "c" () -> bool ---
		hw_calendar_updater_check      :: proc "c" () -> bool ---
		hw_calendar_updater_shutdown   :: proc "c" () ---
		hw_calendar_updater_version    :: proc "c" () -> cstring ---
		hw_calendar_updater_build      :: proc "c" () -> cstring ---
	}

	updater_initialize :: proc() -> bool {
		return hw_calendar_updater_initialize()
	}

	updater_check_for_updates :: proc() -> bool {
		return hw_calendar_updater_check()
	}

	updater_shutdown :: proc() {
		hw_calendar_updater_shutdown()
	}

	updater_enabled :: proc() -> bool {return true}

	updater_version_label :: proc() -> string {
		version := hw_calendar_updater_version()
		build := hw_calendar_updater_build()
		if version == nil || build == nil {return "RELEASE"}
		return fmt.tprintf("%s (%s)", string(version), string(build))
	}
} else {
	updater_initialize :: proc() -> bool {return false}
	updater_check_for_updates :: proc() -> bool {return false}
	updater_shutdown :: proc() {}
	updater_enabled :: proc() -> bool {return false}
	updater_version_label :: proc() -> string {return "DEVELOPMENT"}
}
