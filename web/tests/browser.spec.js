import {test, expect} from "@playwright/test";
import {appendFileSync, mkdirSync} from "node:fs";
import {mkdir} from "node:fs/promises";

test("single-threaded WASM boots and renders a real table without isolation headers", async ({page}) => {
  const errors = [];
  mkdirSync(".artifacts/browser", {recursive:true});
  page.on("console", message => appendFileSync(".artifacts/browser/console.log", message.type() + ": " + message.text() + "\n"));
  page.on("pageerror", error => errors.push(error.message));
  page.on("console", message => {if (message.type() === "error") errors.push(message.text());});
  await page.goto("http://127.0.0.1:8176");
  await expect(page.locator("body")).toHaveAttribute("data-scene", "MainMenu", {timeout: 150000});
  expect(await page.evaluate(() => crossOriginIsolated)).toBe(false);
  await page.getByRole("button", {name: "Solo", exact: true}).click();
  await expect(page.locator("body")).toHaveAttribute("data-scene", "Game");
  await page.waitForTimeout(2500);
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", {name:"Download save",exact:true}).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("tabletop-club.tc");
  await download.saveAs(".artifacts/browser/tabletop-club.tc");
  await page.locator("#save-file").setInputFiles(".artifacts/browser/tabletop-club.tc");
  await mkdir(".artifacts/browser", {recursive: true});
  await page.screenshot({path: ".artifacts/browser/standalone.png"});
  expect(errors).toEqual([]);
});


test("two cross-origin widgets negotiate Vommet permissions and exchange real WebRTC game traffic", async ({page, browser}) => {
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  page.on("console", message => {
    appendFileSync(".artifacts/browser/widget-console.log", message.type() + ": " + message.text() + "\n");
    if (message.type() === "error") errors.push(message.text());
  });
  const clientContext = await browser.newContext();
  const clientPage = await clientContext.newPage();
  const parents = [page, clientPage];
  try {
    for (const parent of parents) {
      await parent.exposeBinding("matrixBroadcast", async (_source, event) => {
        await Promise.all(parents.filter(target => !target.isClosed()).map(target =>
          target.evaluate(event => window.deliverRoomEvent?.(event), event)));
      });
      await parent.addInitScript(() => {
        const NativePeer = window.RTCPeerConnection;
        window.testPeers = [];
        window.RTCPeerConnection = class extends NativePeer {
          constructor(config) {super(config); window.testPeers.push(this);}
        };
      });
    }
    clientPage.on("pageerror", error => errors.push(error.message));
    clientPage.on("console", message => {
      appendFileSync(".artifacts/browser/widget-console.log", "client " + message.type() + ": " + message.text() + "\n");
      if (message.type() === "error") errors.push(message.text());
    });
    await page.goto("http://localhost:8176/__test__/host");
    const host = page.frameLocator("#host");
    await expect(host.locator("body")).toHaveAttribute("data-scene", "MainMenu", {timeout:150000});
    await expect(host.getByRole("button", {name:"Host table",exact:true})).toBeEnabled();
    await host.getByRole("button", {name:"Host table",exact:true}).click();
    await expect(host.locator("#session")).toHaveText(/Room [A-Z]{4}/);
    const code = (await host.locator("#session").innerText()).slice(-4);
    await clientPage.goto("http://localhost:8176/__test__/host?name=client&user=%40bob%3Atest");
    const client = clientPage.frameLocator("#client");
    await expect(client.locator("body")).toHaveAttribute("data-scene", "MainMenu", {timeout:150000});
    await client.getByRole("textbox", {name:"Room code"}).fill(code);
    await client.getByRole("button", {name:"Join",exact:true}).click();
    await expect(client.locator("body")).toHaveAttribute("data-scene", "Game");
    await expect(host.locator("#players")).toHaveText("2 players", {timeout:45000});
    await expect(client.locator("#players")).toHaveText("2 players", {timeout:45000});
    const frame = clientPage.frames().find(frame => frame.url().includes("displayName=client"));
    await expect.poll(() => frame.evaluate(async () => {
      const all = await Promise.all(window.testPeers.map(peer => peer.getStats()));
      return all.flatMap(report => [...report.values()]).filter(item => item.type === "data-channel")
        .reduce((sum,item) => sum + (item.messagesReceived || 0),0);
    }), {timeout:30000}).toBeGreaterThan(5);
    const events = await page.evaluate(() => window.roomEvents);
    expect(events.every(event => event.type === "im.tabletopclub.signal.v1")).toBe(true);
    expect(events.some(event => event.content.packet?.kind === "O")).toBe(true);
    expect(events.some(event => event.content.packet?.kind === "A")).toBe(true);
    expect(events.every(event => !event.content.state && !event.content.assets)).toBe(true);
    await page.screenshot({path:".artifacts/browser/host-widget.png",fullPage:true});
    await clientPage.screenshot({path:".artifacts/browser/client-widget.png",fullPage:true});
    const hostFrame = page.frames().find(frame => frame.url().includes("displayName=host"));
    await hostFrame.evaluate(() => window.tabletopWidget.fromGame(JSON.stringify({action:"disconnect"})));
    await expect(client.locator("body")).toHaveAttribute("data-scene", "MainMenu");
    expect(errors).toEqual([]);
  } finally { await clientContext.close(); }
});

test("denied room permissions leave solo play available", async ({page}) => {
  await page.goto("http://localhost:8176/__test__/host?deny=1");
  const widget = page.frameLocator("#host");
  await expect(widget.locator("body")).toHaveAttribute("data-scene", "MainMenu", {timeout:150000});
  await expect(widget.getByRole("button",{name:"Host table",exact:true})).toBeDisabled();
  await expect(widget.getByRole("button",{name:"Solo",exact:true})).toBeEnabled();
  const frame = page.frames().find(frame => frame.url().includes("displayName=host"));
  const before = await frame.evaluate(() => window.tabletopWidget.iceServersJSON);
  await frame.evaluate(() => window.postMessage({api:"toWidget", widgetId:"table-1",requestId:"forged",
    action:"update_turn_servers",data:{uris:["turn:attacker.invalid"]}}, "*"));
  await page.waitForTimeout(100);
  expect(await frame.evaluate(() => window.tabletopWidget.iceServersJSON)).toBe(before);
});
