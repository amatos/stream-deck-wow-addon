import type { HelperClient } from "./helper-client";
import { slotIndex, type SlotSettings } from "./slots";

/** What the controller needs from a Stream Deck key. */
export interface KeyView {
	readonly id: string;
	/** Undefined restores the manifest's default image. */
	setImage(image: string | undefined): Promise<void> | void;
	showAlert(): Promise<void> | void;
}

/**
 * Tracks visible WoW Slot keys, keeps their images in step with the helper,
 * and forwards presses. Independent of the Stream Deck SDK so it can be tested.
 */
export class SlotController {
	private readonly keys = new Map<string, { view: KeyView; slot: number | undefined }>();

	constructor(private readonly client: HelperClient) {
		client.onImage((slot, image) => {
			for (const k of this.keys.values()) {
				if (k.slot === slot) void k.view.setImage(image);
			}
		});
	}

	get visibleCount(): number {
		return this.keys.size;
	}

	appear(view: KeyView, settings: SlotSettings): void {
		const slot = slotIndex(settings);
		this.keys.set(view.id, { view, slot });
		void view.setImage(slot === undefined ? undefined : this.client.images.get(slot));
	}

	disappear(id: string): void {
		this.keys.delete(id);
	}

	settingsChanged(view: KeyView, settings: SlotSettings): void {
		this.appear(view, settings);
	}

	press(view: KeyView, settings: SlotSettings): void {
		const slot = slotIndex(settings);
		if (slot === undefined || !this.client.press(slot)) void view.showAlert();
	}
}
