const WEEKDAYS = ["일", "월", "화", "수", "목", "금", "토"];

function formatDate(dateStr) {
  const [y, m, d] = dateStr.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  return `${m}월 ${d}일 (${WEEKDAYS[dt.getDay()]})`;
}

async function loadFeed() {
  const feed = document.getElementById("feed");
  try {
    const res = await fetch("manifest.json", { cache: "no-store" });
    const days = await res.json();

    if (!days.length) {
      feed.innerHTML = '<p class="empty">아직 올라온 이미지가 없습니다.</p>';
      return;
    }

    feed.innerHTML = "";
    days.forEach((day) => {
      const section = document.createElement("section");
      section.className = "day";

      const header = document.createElement("div");
      header.className = "day__header";
      header.innerHTML = `<span class="day__date">${formatDate(day.date)}</span><span class="day__count">${day.images.length}장</span>`;
      section.appendChild(header);

      const grid = document.createElement("div");
      grid.className = "day__grid";
      day.images.forEach((item) => {
        const filename = typeof item === "string" ? item : item.file;
        const card = document.createElement("div");
        card.className = "card";

        const img = document.createElement("img");
        img.src = `images/${day.date}/${filename}`;
        img.loading = "lazy";
        img.alt = `${day.date} 공구 이미지`;
        img.addEventListener("click", () => openLightbox(img.src));
        card.appendChild(img);

        if (item && item.krw) {
          const price = document.createElement("div");
          price.className = "card__price";
          price.textContent = `약 ${Number(item.krw).toLocaleString()}원`;
          card.appendChild(price);
        }

        grid.appendChild(card);
      });
      section.appendChild(grid);

      feed.appendChild(section);
    });
  } catch (err) {
    feed.innerHTML = '<p class="empty">목록을 불러오지 못했습니다.</p>';
  }
}

function openLightbox(src) {
  const lightbox = document.getElementById("lightbox");
  document.getElementById("lightboxImg").src = src;
  lightbox.classList.add("is-open");
}

function closeLightbox() {
  document.getElementById("lightbox").classList.remove("is-open");
}

document.getElementById("lightboxClose").addEventListener("click", closeLightbox);
document.getElementById("lightbox").addEventListener("click", (e) => {
  if (e.target.id === "lightbox") closeLightbox();
});

loadFeed();
