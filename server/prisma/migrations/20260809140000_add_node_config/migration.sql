-- CreateTable
CREATE TABLE "NodeConfig" (
    "id" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "NodeConfig_pkey" PRIMARY KEY ("id")
);
