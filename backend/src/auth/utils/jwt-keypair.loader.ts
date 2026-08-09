import { readFileSync } from "node:fs";
import { resolve } from "node:path";

export function loadJwtKey(filePath: string): string {
    return readFileSync(resolve(process.cwd(), filePath), 'utf8');
}