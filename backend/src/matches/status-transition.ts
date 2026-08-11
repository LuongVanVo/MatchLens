import { ConflictException } from "@nestjs/common";
import { MatchStatus } from "@prisma/client";

export type TransitionState = MatchStatus | 'INIT';

export const ALLOWED_TRANSITIONS: Record<TransitionState, MatchStatus[]> = {
    INIT: ['pending'], // Khởi tạo 
    pending: ['uploaded'],
    uploaded: ['processing'],
    processing: ['completed', 'failed'],
    completed: [],
    failed: [],
}

export function assertValidTransition(from: TransitionState, to: MatchStatus): void {
    if (!ALLOWED_TRANSITIONS[from].includes(to)) {
        throw new ConflictException(
            `Cannot transition from '${from}' to '${to}'.`
        );
    }
}