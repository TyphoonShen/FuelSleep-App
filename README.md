# FuelSleep

A personal iPhone app that pulls your sleep and workouts from Apple Health, logs meals from a photo or described text, and tells you what to fix today. For example: *you trained this morning but you're 90g behind on carbs, so add rice or oats to your next meals.*

> A personal project, built with Claude. It isn't on the App Store; you build it yourself with Xcode (see Setup). It is not medical advice.

## What it does

**Today tab**
- **Last night's sleep** from your Apple Watch: total time asleep, bed and wake times, and deep / core / REM / awake.
- **Activity**: today's workouts, active calories and steps. Any workout recorded today makes it a *training day*. If you trained without your Watch, flip the "I trained today" switch.
- **Nutrition**: calories, protein, carbs and fat against your targets. On training days the carb and calorie targets go up automatically.
- **Checks**: free, offline rules that run all the time. They flag low carbs on a training day, protein falling behind, being under-fuelled in the evening, and short sleep. Checks take the time of day into account, so at 1pm you aren't measured against a full day's target.
- **AI coach**: one tap sends today's numbers to Claude and gets back a headline and 2–4 specific tips.

**Meals tab**
- Tap **+** → *Take photo* or *Choose photo*. Claude estimates the meal's name, calories and macros, and you can correct anything before saving. Adding details helps accuracy, e.g. "200g chicken, cooked in butter".
- **Describe or type it:** type or dictate what you ate, e.g. "2 eggs, 2 toast with butter, flat white", and tap *Fill in with AI*. Or skip that and type the numbers yourself.
- **Favourites:** turn on *Save as favourite* when adding a meal, or swipe right on any meal and tap the star. Favourites appear in **Quick add** on the Today tab, so one tap logs them now (with a 4-second *Undo*).
- **Log again:** swipe right on any past meal and tap *Log again*, or long-press it and choose *Adjust & log again* to change the portion first. *+ → Favourites & recent* lists your favourites and the meals you've eaten most in the last 30 days.
- Tap a meal to edit it. Swipe left to delete it.
- Saved meals also go into Apple Health (you can turn this off in Settings).

**History tab**
- A month calendar. Each day shows its score out of 100 and three badges: 🏋️ trained, 🌙 slept well, 🍴 ate well. Tap a day to see the full breakdown, sleep, workouts and meals.
- At the top, the month's average score and how many days you trained, slept well and ate well.
- If you trained without your Watch, tap the day and turn on "I trained this day".

**How the daily score works** (tune the numbers in `Services/Scoring.swift`)
- **Sleep, 35%:** 100 if you're within 15 minutes of your goal, minus 25 points for each extra hour short. 7h on an 8h goal scores 81. "Slept well" means 80 or more.
- **Nutrition, 40%:** how close you got to each target, using training-day targets on training days. Protein counts for 35%, calories 30%, carbs 25% and fat 10%. Being within 10% of a target (20% for fat) counts as hitting it. "Ate well" means 75 or more.
- **Activity, 25%:** 100 on a training day. On rest days it's based on steps, with 10,000 steps scoring 100.
- Parts with no data (for example, no meals logged) are left out and don't count as zero.
- Today's score is "so far": you're compared with how much of the day has passed.
- Colours: 85+ green (Great), 70–84 blue (Good), 50–69 orange (Fair), under 50 red (Poor).

**Weekly review** (top of the History tab; also on Today on Sundays and Mondays)
- Your week's average score compared with last week, plus days trained, nights slept well, days ate well and average sleep.
- Charts of your daily score, sleep against your goal, and carbs as a % of target with training and rest days in different colours. Tap a bar to see that day's numbers.
- **Targets hit:** how many logged days you hit calories, protein, carbs and fat.
- **Coach's review:** an AI summary with what went well, one focus for next week, and a short plan. About 1p, and it's saved so reopening the week costs nothing.
- Use the arrows to look at earlier weeks.

**Themes** (Settings → Appearance)
- **Classic**, **Halloween 🎃**, or **Automatic**, which is Halloween from 15–31 October and Classic the rest of the year.
- Halloween gives you midnight-purple screens, pumpkin and slime colours, a jack-o'-lantern score ring, 🦇 / ⚰️ / 🎃 badges, spooky score labels (Spooktacular, Wicked good, Haunted, Cursed), floating bats on Today, a pumpkin app icon, and an AI coach with a light spooky tone.
- To add a new theme, copy `AppTheme.halloween` in `Models/Theme.swift` and add a case to `ThemeChoice`.

**Settings tab**: targets, extra carbs for training days, sleep goal, your API key, the model choice, and a running spend estimate.

## What the AI costs

The AI bills separately from any Claude.ai subscription, through an API account. Approximate cost per request:

| | Sonnet 5.5 (default, more accurate) | Haiku 5.5 (cheapest) |
|---|---|---|
| One meal photo | ~$0.006 (about 0.5p) | ~$0.0003 |
| One coach request | ~$0.006 | ~$0.0003 |
| A typical day (4 photos + 2 coach requests) | **~3–4p** | **well under 1p** |

Prices at the time of writing: Sonnet 5.5 is $2 per million input tokens and $10 per million output; Haiku 5.5 is $0.10 / $0.50. The Settings tab keeps a running estimate. The console shows the exact amount.

Recommendation: start on Sonnet for meal photos, since accuracy matters most there. Switch to Haiku in Settings if you want it nearly free.

## Setup (about 30 minutes the first time)

You need a Mac, your iPhone, a USB cable, and a free Apple ID.

### 1. Install the tools on your Mac
1. Install **Xcode** from the Mac App Store (it's large, so start this first). Open it once and let it install its components.
2. Install **Homebrew** if you don't have it: see https://brew.sh. In Terminal, run:
   ```
   brew install xcodegen
   ```

### 2. Generate the Xcode project
1. Download this repository (**Code → Download ZIP** on GitHub) and unzip it, e.g. into your Documents folder as `FuelSleep`.
2. Open `project.yml` in any text editor and change the bundle ID `com.tayfun.fuelsleep` to something unique to you, e.g. `com.yourname.fuelsleep`.
3. In Terminal:
   ```
   cd ~/Documents/FuelSleep
   xcodegen
   open FuelSleep.xcodeproj
   ```

### 3. Sign it with your Apple ID
1. In Xcode, go to **Xcode → Settings → Accounts → +** and sign in with your Apple ID.
2. Click the blue **FuelSleep** project at the top of the left sidebar, then select the **FuelSleep** target and open the **Signing & Capabilities** tab.
3. Tick **Automatically manage signing** and choose your name (Personal Team) under **Team**.
4. Check that **HealthKit** is listed under capabilities. It should already be there. If not, click **+ Capability** and add it.

### 4. Run it on your iPhone
1. Plug in your iPhone and tap **Trust** on the phone.
2. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode**. The phone restarts.
3. In Xcode, pick your iPhone from the device menu at the top, then press **▶ Run** (⌘R).
4. The first time, the iPhone will refuse to open the app. Go to **Settings → General → VPN & Device Management**, tap your Apple ID and choose **Trust**. Then open FuelSleep.
5. Allow all the Health permissions when asked.

> **Free Apple ID limit:** apps installed this way stop opening after **7 days**. To fix that, plug the phone in and press Run again; your data is kept. A paid Apple Developer account ($99/year) extends this to a year.

### 5. Turn on the AI
1. Go to https://platform.claude.com, sign up, and add a small prepaid credit under Billing (a few dollars lasts months).
2. Create an API key under **API Keys**.
3. In FuelSleep, open **Settings → AI**, paste the key and tap **Save key**. The key is stored in the iPhone Keychain.

Treat the key like a password. Anyone who has it can spend your credit. You can also set a monthly spend limit in the console.

### 6. Set your targets
Open **Settings** and enter your calorie, protein, carb and fat targets. The defaults (2500 kcal, 150g protein, 280g carbs, 80g fat, +60g carbs on training days) are only a placeholder.

## For sleep data to show up
- Wear your Watch to bed with a **Sleep** schedule set in the Health app (Browse → Sleep). Stages (deep/core/REM) need watchOS 9 or later.
- The app counts sleep between 6pm yesterday and 2pm today, and uses only one device's data so sleep isn't counted twice.

## How the code is organised

```
FuelSleep/
  FuelSleepApp.swift        App entry and the three tabs
  Models/
    Meal.swift              A logged meal (stored on the phone with SwiftData)
    Goals.swift             Targets and training-day adjustment
    Theme.swift             Colours, labels and badges for each theme
  Services/
    HealthStore.swift       Reads sleep, workouts and activity; writes meals to Health
    ClaudeService.swift     Calls the Claude API: meal photo → macros, day → advice
    RulesEngine.swift       The free offline checks, plus the summary sent to the coach
    Scoring.swift           The daily score out of 100
    WeeklyStats.swift       Weekly numbers, and the saved AI reviews
    Keychain.swift          Stores the API key securely
    MealLogger.swift        Saves meals and favourites (used by every way of logging)
  Views/                    Today, Meals, History calendar, Day detail, Add/Edit meal, Settings, camera
```

**Changing the checks:** edit `RulesEngine.swift`. Each check is a short `if` block.

**Changing how the AI responds:** edit the `system` text in `ClaudeService.swift`. Each call uses structured outputs (a JSON schema), so the app always gets clean numbers instead of free text.
