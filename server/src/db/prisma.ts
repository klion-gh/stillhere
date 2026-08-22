/**
 * The database client, shared by every module.
 */
import { PrismaClient } from "@prisma/client";

export const prisma = new PrismaClient();
