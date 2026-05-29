// AIdeas PDF — MuPDF WASM bridge
// Espone window.mupdfBridge.applyChanges(pdfBytes, annotationsJson) → Promise<Uint8Array>

(async function () {
  try {
    const mupdf = await import('./mupdf.js');
    await mupdf.ready;

    window.mupdfBridge = {
      ready: true,

      async applyChanges(pdfBytes, annotationsJson) {
        const data = JSON.parse(annotationsJson);
        const doc = mupdf.Document.openDocument(
          new Uint8Array(pdfBytes),
          'application/pdf'
        );

        try {
          const numPages = doc.countPages();

          for (let pi = 0; pi < numPages; pi++) {
            const pageNum = pi + 1;
            const page = doc.loadPage(pi);
            const bounds = page.getBounds();          // [x0, y0, x1, y1]
            const pageW = bounds[2] - bounds[0];
            const pageH = bounds[3] - bounds[1];

            // ── 1. Redazioni (rimuovono contenuto dal content stream) ──────
            let needsRedact = false;

            for (const ann of (data.annotations || [])) {
              if (ann.page !== pageNum || ann.type !== 'redact') continue;
              const rect = normToPdf(ann.x, ann.y, ann.w, ann.h, pageW, pageH);
              const a = page.createAnnotation('Redact');
              a.setRect(rect);
              a.setColors({ fill: [0, 0, 0] });
              a.update();
              needsRedact = true;
            }

            for (const edit of (data.textEdits || [])) {
              if (edit.page !== pageNum || !edit.deleted) continue;
              // coords assoluti PDF (da extractText, già in PDF points)
              const rect = [
                edit.origX,
                pageH - edit.origY - edit.origFontSize * 1.5,
                edit.origX + edit.origWidth,
                pageH - edit.origY,
              ];
              const a = page.createAnnotation('Redact');
              a.setRect(rect);
              a.setColors({ fill: [1, 1, 1], stroke: [1, 1, 1] });
              a.update();
              needsRedact = true;
            }

            for (const edit of (data.imageEdits || [])) {
              if (edit.page !== pageNum || !edit.deleted) continue;
              const rect = [
                edit.origX,
                pageH - edit.origY - edit.origHeight,
                edit.origX + edit.origWidth,
                pageH - edit.origY,
              ];
              const a = page.createAnnotation('Redact');
              a.setRect(rect);
              a.setColors({ fill: [1, 1, 1], stroke: [1, 1, 1] });
              a.update();
              needsRedact = true;
            }

            if (needsRedact) {
              page.applyRedactions(true, 2); // blackBoxes=true, imageMethod=SUBSAMPLE
            }

            // ── 2. Annotazioni visive (PDF annotation objects nativi) ──────
            for (const ann of (data.annotations || [])) {
              if (ann.page !== pageNum || ann.type === 'redact') continue;
              addAnnotation(page, ann, pageW, pageH);
            }

            page.destroy();
          }

          const buf = doc.saveToBuffer('compress');
          const result = buf.asUint8Array().slice(); // copia prima di distruggere
          buf.destroy();
          return result;

        } finally {
          doc.destroy();
        }
      },
    };

    console.log('[AIdeas PDF] MuPDF WASM bridge pronto');

  } catch (e) {
    console.error('[AIdeas PDF] MuPDF WASM non disponibile:', e);
    window.mupdfBridge = { ready: false };
  }
})();

// ── Helpers ──────────────────────────────────────────────────────────────────

// Converte coordinate normalizzate [0,1] top-left → PDF points bottom-left
function normToPdf(x, y, w, h, pageW, pageH) {
  return [
    x * pageW,
    pageH * (1 - y - h),
    (x + w) * pageW,
    pageH * (1 - y),
  ];
}

function rgbNorm(color) {
  // color è [r, g, b] 0-255
  return [color[0] / 255, color[1] / 255, color[2] / 255];
}

function addAnnotation(page, ann, pageW, pageH) {
  const rect = normToPdf(ann.x, ann.y, ann.w || 0.001, ann.h || 0.001, pageW, pageH);
  const rgb  = rgbNorm(ann.color);

  switch (ann.type) {

    case 'text': {
      if (!ann.text) return;
      const a = page.createAnnotation('FreeText');
      a.setRect(rect);
      a.setContents(ann.text);
      a.setDefaultAppearance(
        mapFont(ann.fontFamily),
        ann.fontSize || 14,
        rgb
      );
      a.update();
      break;
    }

    case 'rect': {
      const a = page.createAnnotation('Square');
      a.setRect(rect);
      a.setColors({ stroke: rgb });
      a.setBorderWidth(ann.lineWidth || 1);
      a.update();
      break;
    }

    case 'highlight': {
      const a = page.createAnnotation('Highlight');
      a.setRect(rect);
      a.setColors({ stroke: [1, 0.84, 0] });
      a.update();
      break;
    }

    case 'draw': {
      if (!ann.points || ann.points.length < 2) return;
      // Ink list: array di stroke, ogni stroke è un array piatto [x1,y1,x2,y2,...]
      const inkStroke = ann.points.flatMap(p => [
        p.dx * pageW,
        pageH * (1 - p.dy),
      ]);
      const a = page.createAnnotation('Ink');
      a.setInkList([inkStroke]);
      a.setColors({ stroke: rgb });
      a.setBorderWidth(ann.lineWidth || 1);
      a.update();
      break;
    }

    // image: non supportata come annotazione PDF nativa in questa versione
  }
}

function mapFont(family) {
  if (!family) return 'Helvetica';
  const f = family.toLowerCase();
  if (f.includes('times')) return 'Times-Roman';
  if (f.includes('courier')) return 'Courier';
  return 'Helvetica';
}
