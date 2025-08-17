 
import { describe, it, expect, beforeEach } from "vitest";

interface Petition {
	creator: string;
	title: string;
	description: string;
	threshold: bigint;
	startBlock: bigint;
	endBlock: bigint;
	signatureCount: bigint;
	status: string;
}

interface MockContract {
	admin: string;
	paused: boolean;
	petitionCounter: bigint;
	citizenTokenContract: string;
	petitions: Map<bigint, Petition>;
	signatures: Map<bigint, Map<string, boolean>>;
	blockHeight: bigint;

	isAdmin(caller: string): boolean;
	isVerifiedCitizen(caller: string): boolean;
	setPaused(
		caller: string,
		pause: boolean
	): { value: boolean } | { error: number };
	createPetition(
		caller: string,
		title: string,
		description: string,
		threshold: bigint,
		duration: bigint
	): { value: bigint } | { error: number };
	signPetition(
		caller: string,
		petitionId: bigint
	): { value: boolean } | { error: number };
	withdrawSignature(
		caller: string,
		petitionId: bigint
	): { value: boolean } | { error: number };
	closePetition(
		caller: string,
		petitionId: bigint
	): { value: boolean } | { error: number };
}

const mockContract: MockContract = {
	admin: "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM",
	paused: false,
	petitionCounter: 0n,
	citizenTokenContract: "SP000000000000000000002Q6VF78",
	petitions: new Map<bigint, Petition>(),
	signatures: new Map<bigint, Map<string, boolean>>(),
	blockHeight: 100n,

	isAdmin(caller: string): boolean {
		return caller === this.admin;
	},

	isVerifiedCitizen(caller: string): boolean {
		return true; // Mocked for tests
	},

	setPaused(
		caller: string,
		pause: boolean
	): { value: boolean } | { error: number } {
		if (!this.isAdmin(caller)) return { error: 100 };
		this.paused = pause;
		return { value: pause };
	},

	createPetition(
		caller: string,
		title: string,
		description: string,
		threshold: bigint,
		duration: bigint
	): { value: bigint } | { error: number } {
		if (this.paused) return { error: 108 };
		if (!this.isVerifiedCitizen(caller)) return { error: 111 };
		if (threshold < 10n) return { error: 107 };
		if (duration < 144n || duration > 52560n) return { error: 106 };
		const petitionId = this.petitionCounter + 1n;
		if (petitionId > 10000n) return { error: 112 };
		this.petitions.set(petitionId, {
			creator: caller,
			title,
			description,
			threshold,
			startBlock: this.blockHeight,
			endBlock: this.blockHeight + duration,
			signatureCount: 0n,
			status: "active",
		});
		this.petitionCounter = petitionId;
		return { value: petitionId };
	},

	signPetition(
		caller: string,
		petitionId: bigint
	): { value: boolean } | { error: number } {
		if (this.paused) return { error: 108 };
		if (!this.isVerifiedCitizen(caller)) return { error: 111 };
		const petition = this.petitions.get(petitionId);
		if (!petition) return { error: 101 };
		if (petition.status !== "active") return { error: 104 };
		if (this.blockHeight > petition.endBlock) return { error: 110 };
		let sigMap = this.signatures.get(petitionId) || new Map<string, boolean>();
		if (sigMap.get(caller)) return { error: 102 };
		sigMap.set(caller, true);
		this.signatures.set(petitionId, sigMap);
		petition.signatureCount += 1n;
		if (petition.signatureCount >= petition.threshold) {
			petition.status = "successful";
		}
		this.petitions.set(petitionId, petition);
		return { value: true };
	},

	withdrawSignature(
		caller: string,
		petitionId: bigint
	): { value: boolean } | { error: number } {
		if (this.paused) return { error: 108 };
		const petition = this.petitions.get(petitionId);
		if (!petition) return { error: 101 };
		if (petition.status !== "active") return { error: 104 };
		if (this.blockHeight > petition.endBlock) return { error: 110 };
		let sigMap = this.signatures.get(petitionId) || new Map<string, boolean>();
		if (!sigMap.get(caller)) return { error: 103 };
		sigMap.delete(caller);
		this.signatures.set(petitionId, sigMap);
		petition.signatureCount -= 1n;
		this.petitions.set(petitionId, petition);
		return { value: true };
	},

	closePetition(
		caller: string,
		petitionId: bigint
	): { value: boolean } | { error: number } {
		if (this.paused) return { error: 108 };
		const petition = this.petitions.get(petitionId);
		if (!petition) return { error: 101 };
		if (!this.isAdmin(caller) && caller !== petition.creator)
			return { error: 100 };
		if (petition.status !== "active") return { error: 104 };
		if (this.blockHeight > petition.endBlock) {
			petition.status = "expired";
		} else {
			petition.status = "closed";
		}
		this.petitions.set(petitionId, petition);
		return { value: true };
	},
};

describe("PoliVote Petition Management", () => {
	beforeEach(() => {
		mockContract.admin = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
		mockContract.paused = false;
		mockContract.petitionCounter = 0n;
		mockContract.petitions = new Map();
		mockContract.signatures = new Map();
		mockContract.blockHeight = 100n;
	});

	it("should create a petition when called by verified citizen", () => {
		const result = mockContract.createPetition(
			"ST2CY5...",
			"Test Title",
			"Test Desc",
			10n,
			144n
		);
		expect(result).toEqual({ value: 1n });
		const petition = mockContract.petitions.get(1n);
		expect(petition?.title).toBe("Test Title");
		expect(petition?.threshold).toBe(10n);
		expect(petition?.status).toBe("active");
	});

	it("should prevent creation with invalid threshold", () => {
		const result = mockContract.createPetition(
			"ST2CY5...",
			"Test",
			"Desc",
			5n,
			144n
		);
		expect(result).toEqual({ error: 107 });
	});

	it("should sign a petition", () => {
		mockContract.createPetition("ST2CY5...", "Test", "Desc", 10n, 144n);
		const result = mockContract.signPetition("ST3NB...", 1n);
		expect(result).toEqual({ value: true });
		const petition = mockContract.petitions.get(1n);
		expect(petition?.signatureCount).toBe(1n);
		const sigMap = mockContract.signatures.get(1n);
		expect(sigMap?.get("ST3NB...")).toBe(true);
	});

	it("should prevent duplicate signing", () => {
		mockContract.createPetition("ST2CY5...", "Test", "Desc", 10n, 144n);
		mockContract.signPetition("ST3NB...", 1n);
		const result = mockContract.signPetition("ST3NB...", 1n);
		expect(result).toEqual({ error: 102 });
	});

	it("should withdraw signature", () => {
		mockContract.createPetition("ST2CY5...", "Test", "Desc", 10n, 144n);
		mockContract.signPetition("ST3NB...", 1n);
		const result = mockContract.withdrawSignature("ST3NB...", 1n);
		expect(result).toEqual({ value: true });
		const petition = mockContract.petitions.get(1n);
		expect(petition?.signatureCount).toBe(0n);
		const sigMap = mockContract.signatures.get(1n);
		expect(sigMap?.get("ST3NB...")).toBeUndefined();
	});

	it("should close petition when expired", () => {
		mockContract.createPetition("ST2CY5...", "Test", "Desc", 10n, 144n);
		mockContract.blockHeight = 300n;
		const result = mockContract.closePetition("ST2CY5...", 1n);
		expect(result).toEqual({ value: true });
		const petition = mockContract.petitions.get(1n);
		expect(petition?.status).toBe("expired");
	});

	it("should not allow actions when paused", () => {
		mockContract.setPaused(mockContract.admin, true);
		const result = mockContract.createPetition(
			"ST2CY5...",
			"Test",
			"Desc",
			10n,
			144n
		);
		expect(result).toEqual({ error: 108 });
	});
});