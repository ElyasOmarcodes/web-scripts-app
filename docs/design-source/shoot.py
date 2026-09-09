"""Render every mockup page to a retina PNG."""

from pathlib import Path

from chromedriver_py import binary_path
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service

HERE = Path(__file__).parent
OUT = Path("/home/user/web-scripts-app/docs/screenshots")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    options = Options()
    options.binary_location = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--hide-scrollbars")
    options.add_argument("--force-device-scale-factor=2")
    options.add_argument("--window-size=1440,1260")
    options.add_argument("--font-render-hinting=none")

    driver = webdriver.Chrome(service=Service(binary_path), options=options)
    try:
        for path in sorted(HERE.glob("*.html")):
            driver.get(path.as_uri())
            driver.execute_script("return document.fonts.ready;")
            stage = driver.find_element("css selector", ".stage")
            target = OUT / f"{path.stem}.png"
            stage.screenshot(str(target))
            size = target.stat().st_size // 1024
            print(f"  {target.name:<28} {size} KB")
    finally:
        driver.quit()


if __name__ == "__main__":
    main()
