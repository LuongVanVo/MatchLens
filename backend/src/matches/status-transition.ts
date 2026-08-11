import { ConflictException } from "@nestjs/common";
import { MatchStatus } from "@prisma/client";

export const ALLOWED_TRANSITIONS: Record<MatchStatus, MatchStatus[]> = {
    pending: ['uploaded'],
    uploaded: ['processing'],
    processing: ['completed', 'failed'],
    completed: [],
    failed: [],
}

export function assertValidTransition(from: MatchStatus, to: MatchStatus): void {
    if (!ALLOWED_TRANSITIONS[from].includes(to)) {
        throw new ConflictException(
            `Cannot transition from '${from}' to '${to}'.`
        );
    }
}