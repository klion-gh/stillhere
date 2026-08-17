-- CreateTable
CREATE TABLE "Setting" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Setting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "DiagnosticEvent" (
    "id" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "userId" TEXT,
    "username" TEXT,
    "source" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "detail" TEXT,
    "data" JSONB,

    CONSTRAINT "DiagnosticEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DiagnosticEvent_at_idx" ON "DiagnosticEvent"("at");

-- CreateIndex
CREATE INDEX "DiagnosticEvent_userId_at_idx" ON "DiagnosticEvent"("userId", "at");
