import assert from "node:assert/strict";
import { test } from "node:test";
import {
  dropPendingCall,
  holdCallCandidate,
  holdCallOffer,
  takePendingCall,
} from "./pending_calls.js";

const CALLEE = "callee-1";
const CONV = "conv-1";

const offer = { type: "call:offer", conversationId: CONV, sdp: "v=0" };
const candidate = (n: number) => ({ type: "call:ice-candidate", conversationId: CONV, candidate: `c${n}` });

test("candidates trickled while the callee wakes are delivered after the offer", () => {
  holdCallOffer(CALLEE, CONV, offer);
  for (let i = 0; i < 20; i++) holdCallCandidate(CALLEE, CONV, candidate(i));

  const held = takePendingCall(CALLEE);
  assert.ok(held);
  assert.deepEqual(held.offer, offer);
  assert.equal(held.candidates.length, 20, "every trickled candidate survives the wake window");
  // Order matters: ICE expects them in the order the caller produced them.
  assert.deepEqual(held.candidates[0], candidate(0));
  assert.deepEqual(held.candidates[19], candidate(19));
});

test("taking the call twice yields nothing the second time", () => {
  holdCallOffer(CALLEE, CONV, offer);
  holdCallCandidate(CALLEE, CONV, candidate(0));
  assert.ok(takePendingCall(CALLEE));
  assert.equal(takePendingCall(CALLEE), null);
});

test("a candidate with no parked call is ignored", () => {
  assert.equal(holdCallCandidate(CALLEE, CONV, candidate(0)), false);
  assert.equal(takePendingCall(CALLEE), null);
});

test("a candidate for a different conversation is ignored", () => {
  holdCallOffer(CALLEE, CONV, offer);
  assert.equal(holdCallCandidate(CALLEE, "some-other-conversation", candidate(0)), false);

  const held = takePendingCall(CALLEE);
  assert.ok(held);
  assert.equal(held.candidates.length, 0);
});

test("the number held is capped", () => {
  holdCallOffer(CALLEE, CONV, offer);
  let accepted = 0;
  for (let i = 0; i < 500; i++) {
    if (holdCallCandidate(CALLEE, CONV, candidate(i))) accepted++;
  }
  assert.equal(accepted, 60);

  const held = takePendingCall(CALLEE);
  assert.equal(held?.candidates.length, 60);
});

test("the caller hanging up discards the candidates too", () => {
  holdCallOffer(CALLEE, CONV, offer);
  holdCallCandidate(CALLEE, CONV, candidate(0));
  dropPendingCall(CALLEE, CONV);
  assert.equal(takePendingCall(CALLEE), null);
});

test("hanging up a different call leaves this one parked", () => {
  holdCallOffer(CALLEE, CONV, offer);
  holdCallCandidate(CALLEE, CONV, candidate(0));
  dropPendingCall(CALLEE, "some-other-conversation");

  const held = takePendingCall(CALLEE);
  assert.ok(held);
  assert.equal(held.candidates.length, 1);
});
