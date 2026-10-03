// Hero demo: replays typing a word, the candidate list for each prefix, and
// the Space commit. The candidate lists are what the bundled dictionary
// offers for each prefix, with the rule reading last.
(() => {
  const words = [
    {
      out: "नमस्ते",
      steps: {
        n: ["नाम", "नब्बे", "नमस्कार", "नमस्ते", "न"],
        na: ["नाम", "नब्बे", "नमस्कार", "नमस्ते", "न"],
        nam: ["नाम", "नमस्कार", "नमस्ते", "नामले", "नम"],
        nama: ["नाम", "नमस्कार", "नमस्ते", "नामले", "नम"],
        namas: ["नमस्कार", "नमस्ते", "नामस्थानमा", "नामसँग", "नमस"],
        namast: ["नमस्ते", "नामस्थानमा", "नमस्त"],
        namaste: ["नमस्ते", "नामस्ते"],
      },
    },
    {
      out: "सजिलो",
      steps: {
        s: ["साल", "सात", "साथी", "साठी", "स"],
        sa: ["साल", "सात", "साथी", "साठी", "स"],
        saj: ["साझा", "साझेदारी", "सजिलो", "सजाय", "सज"],
        saji: ["सजिलो", "साजिद", "सजिएको", "सजिएका", "सजि"],
        sajil: ["सजिलो", "सजिलोसँग", "सजिलैसित", "सजिल"],
        sajilo: ["सजिलो", "सजिलोसँग"],
      },
    },
  ];

  const stage = document.querySelector(".demo-stage");
  if (!stage) return;
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const committed = stage.querySelector(".demo-committed");
  const marked = stage.querySelector(".demo-marked");
  const panel = stage.querySelector(".demo-panel");
  // Pause while the pointer is over the demo (WCAG 2.2.2), and stop for
  // good after a few rounds, resting on the last frame.
  let paused = false;
  stage.addEventListener("pointerenter", () => (paused = true));
  stage.addEventListener("pointerleave", () => (paused = false));
  const sleep = async (ms) => {
    await new Promise((r) => setTimeout(r, ms));
    while (paused || document.hidden) await new Promise((r) => setTimeout(r, 200));
  };

  const showCandidates = (list) => {
    panel.replaceChildren(
      ...list.map((text, i) => {
        const li = document.createElement("li");
        if (i === 0) li.className = "is-selected";
        const num = document.createElement("span");
        num.className = "demo-num";
        num.textContent = String(i + 1);
        const word = document.createElement("span");
        word.lang = "ne";
        word.textContent = text;
        li.append(num, word);
        return li;
      }),
    );
    // The panel opens under the start of the word being typed, as in the IME.
    stage.style.setProperty("--demo-panel-x", `${marked.offsetLeft}px`);
  };

  const run = async () => {
    await sleep(1800); // let the reader see the static frame first
    for (let round = 0; round < 3; round++) {
      for (const word of words) {
        committed.textContent = "";
        marked.textContent = "";
        panel.replaceChildren();
        await sleep(700);
        for (const [prefix, list] of Object.entries(word.steps)) {
          marked.textContent = prefix;
          showCandidates(list);
          await sleep(150 + Math.random() * 110);
        }
        await sleep(1300);
        // Space: commit the highlighted candidate.
        marked.textContent = "";
        panel.replaceChildren();
        committed.textContent = word.out + " ";
        await sleep(2200);
      }
    }
    // Rest on the same frame the page shows without JS.
    committed.textContent = "";
    marked.textContent = "namaste";
    showCandidates(words[0].steps.namaste);
  };

  run();
})();

// Guide index: mark the section being read.
(() => {
  const links = new Map(
    [...document.querySelectorAll(".guide-index a")].map((a) => [a.hash.slice(1), a]),
  );
  if (!links.size || !("IntersectionObserver" in window)) return;
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        links.forEach((a) => a.removeAttribute("aria-current"));
        links.get(entry.target.id)?.setAttribute("aria-current", "true");
      }
    },
    { rootMargin: "0px 0px -70% 0px" },
  );
  document.querySelectorAll(".doc-section").forEach((s) => observer.observe(s));
})();
