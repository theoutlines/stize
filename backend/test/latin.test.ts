import { describe, expect, it } from "vitest";
import { toLatin } from "../src/lib/latin";
import { shortAddress } from "../src/lib/geocode";

describe("toLatin", () => {
  it("transliterates Serbian Cyrillic, digraphs keep case", () => {
    expect(toLatin("Трг републике")).toBe("Trg republike");
    expect(toLatin("Љубљанска, ЊЕГОШЕВА, Џорџа")).toBe("Ljubljanska, NJEGOŠEVA, Džordža");
    expect(toLatin("Линија 708, ECO 1")).toBe("Linija 708, ECO 1");
  });
});

describe("shortAddress", () => {
  it("uses street + number and district", () => {
    expect(
      shortAddress({
        display_name: "5, Кнез Михаилова, Стари град, Београд, Србија",
        address: { road: "Кнез Михаилова", house_number: "5", suburb: "Стари град", city: "Београд" },
      }),
    ).toBe("Knez Mihailova 5, Stari grad");
  });
  it("prefers a named place over the road", () => {
    expect(
      shortAddress({
        display_name: "Трг републике, Скадарлија, Београд",
        name: "Трг републике",
        address: { road: "Васе Чарапића", neighbourhood: "Скадарлија" },
      }),
    ).toBe("Trg republike, Skadarlija");
  });
});
