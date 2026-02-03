#!/bin/bash

# ============================================================
# Riven Show Cleanup & Management Script (Enhanced Version)
# ============================================================
# This script helps you manage show states in the Riven database
# including deleting episodes, marking as unreleased, and 
# updating states for episodes, seasons, and shows.
# ============================================================

# Function to check if the Docker container is running
check_container_status() {
    docker ps | grep -q "riven-db"
    if [ $? -ne 0 ]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║  ERROR: The 'riven-db' container is not running!          ║"
        echo "║  Please start the container and try again.                ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        exit 1
    fi
}

# Function to create a backup of the database
backup_database() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    DATABASE BACKUP                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "RECOMMENDED: Creating a backup allows you to restore your"
    echo "database if something goes wrong. The backup will be stored"
    echo "at '/tmp/riven_backup.sql' on your host machine."
    echo ""
    read -p "Do you want to create a backup? (y/n): " backup_choice
    if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Creating backup of the database..."
        # Backup inside the container at /tmp/riven_backup.sql
        docker exec riven-db pg_dump -U postgres -d riven -f /tmp/riven_backup.sql
        if [ $? -eq 0 ]; then
            echo "✓ Backup successful inside the container at /tmp/riven_backup.sql."
            # Copy the backup file from the container to the host
            docker cp riven-db:/tmp/riven_backup.sql /tmp/riven_backup.sql
            if [ $? -eq 0 ]; then
                echo "✓ Backup file successfully copied to the host at /tmp/riven_backup.sql."
                echo ""
            else
                echo "✗ Error: Failed to copy the backup file from the container to the host."
                echo "Exiting script for safety."
                exit 1
            fi
        else
            echo "✗ Error: Backup failed inside the container."
            echo "Exiting script for safety."
            exit 1
        fi
    else
        echo "⚠ Skipping backup. Proceeding without backup protection."
        echo ""
    fi
}

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Riven Show Cleanup & Management Script            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 0: Check if the Docker container is running
check_container_status

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     FIND YOUR SHOW                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Search for the show by:"
echo "  1) TVDB ID (exact match - fastest if you know the ID)"
echo "  2) Show Name (partial match - searches titles containing your text)"
echo ""
read -p "Enter choice (1 or 2): " search_choice

if [ "$search_choice" == "1" ]; then
    read -p "Enter TVDB ID: " tvdb_id
    search_condition="mi_show.tvdb_id = '$tvdb_id'"
elif [ "$search_choice" == "2" ]; then
    read -p "Enter show name (partial match works): " show_name
    search_condition="mi_show.title ILIKE '%$show_name%'"
else
    echo "✗ Invalid choice. Exiting."
    exit 1
fi

# Find the parent show(s)
result=$(docker exec riven-db psql -U postgres -d riven -t -A -F',' -c "
SELECT mi_show.id, mi_show.title
FROM \"MediaItem\" mi_show
WHERE mi_show.type = 'show'
AND $search_condition;")

show_count=$(echo "$result" | grep -v '^$' | wc -l)

if [ "$show_count" -eq 0 ]; then
    echo "✗ No shows found. Exiting."
    exit 0
elif [ "$show_count" -gt 1 ]; then
    echo ""
    echo "Multiple shows found. Please choose the correct one:"
    echo "──────────────────────────────────────────────────"
    echo "$result" | while IFS=',' read -r id title; do
        echo "  ID: $id | Title: $title"
    done
    echo ""
    read -p "Enter the ID of the show you want to manage: " show_id
    show_title=$(docker exec riven-db psql -U postgres -d riven -t -c "SELECT title FROM \"MediaItem\" WHERE id = $show_id;" | xargs)
else
    show_id=$(echo "$result" | cut -d',' -f1)
    show_title=$(echo "$result" | cut -d',' -f2)
    echo ""
    echo "✓ Found: $show_title (ID: $show_id)"
    echo ""
    read -p "Proceed with this show? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy](es)?$ ]] && exit 0
fi

final_condition="parent.id = $show_id"

# Create backup before making any changes
backup_database

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              CURRENT STATE SUMMARY                         ║"
echo "║  Show: $show_title"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
docker exec riven-db psql -U postgres -d riven -c "
SELECT mi.last_state AS state, COUNT(*) AS count
FROM \"MediaItem\" mi
INNER JOIN \"Episode\" e ON mi.id = e.id
INNER JOIN \"Season\" s ON e.parent_id = s.id
INNER JOIN \"Show\" sh ON s.parent_id = sh.id
INNER JOIN \"MediaItem\" parent ON sh.id = parent.id
WHERE $final_condition
GROUP BY mi.last_state;"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║               STEP 1: DELETE EPISODES                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠ WHAT THIS DOES:"
echo "  • Permanently REMOVES episodes from the database"
echo "  • Riven will FORGET about these episodes and STOP trying to find them"
echo "  • Deleted episodes will NOT appear in your library or search results"
echo "  • To restore deleted episodes, you must do a FULL SHOW RESET/RE-ADD"
echo ""
echo "WHEN TO USE THIS:"
echo "  • Remove episodes that don't exist (specials, bonus content, etc.)"
echo "  • Clean up incorrectly indexed episodes"
echo "  • Remove episodes you never want Riven to search for"
echo ""
echo "Available states you might want to delete:"
echo "  • Indexed - Episodes that were found but not yet scraped"
echo "  • Unknown - Episodes that Riven couldn't find streams for"
echo "  • Failed - Episodes that had errors during processing"
echo "  • Scraped - Episodes that have been scraped but not downloaded"
echo ""
read -p "Enter state name to DELETE those episodes (or press Enter to skip): " raw_target_state

# Format input to Title Case (e.g., indexed -> Indexed)
target_state=$(echo "${raw_target_state,,}" | sed 's/./\u&/')

deleted_count=0
affected_seasons=""

if [ ! -z "$target_state" ]; then
    echo ""
    echo "⚠ WARNING: You are about to DELETE all episodes with state: $target_state"
    read -p "Are you absolutely sure? Type 'DELETE' to confirm: " delete_confirm
    
    if [ "$delete_confirm" == "DELETE" ]; then
        affected_seasons=$(docker exec riven-db psql -U postgres -d riven -t -c "
            SELECT DISTINCT s.number
            FROM \"MediaItem\" mi
            INNER JOIN \"Episode\" e ON mi.id = e.id
            INNER JOIN \"Season\" s ON e.parent_id = s.id
            INNER JOIN \"Show\" sh ON s.parent_id = sh.id
            INNER JOIN \"MediaItem\" parent ON sh.id = parent.id
            WHERE $final_condition AND mi.last_state = '$target_state'
            ORDER BY s.number;" | xargs | sed 's/ /,/g')

        if [ ! -z "$affected_seasons" ]; then
            docker exec riven-db psql -U postgres -d riven -c "DELETE FROM \"MediaItem\" WHERE id IN (SELECT mi.id FROM \"MediaItem\" mi INNER JOIN \"Episode\" e ON mi.id = e.id INNER JOIN \"Season\" s ON e.parent_id = s.id INNER JOIN \"Show\" sh ON s.parent_id = sh.id INNER JOIN \"MediaItem\" parent ON sh.id = parent.id WHERE $final_condition AND mi.last_state = '$target_state');"
            echo "✓ Episodes deleted in Season(s): $affected_seasons"
            deleted_count=1
        else
            echo "ℹ No episodes found with state '$target_state'"
        fi
    else
        echo "⚠ Deletion cancelled. No episodes were deleted."
    fi
else
    echo "ℹ Skipping deletion step."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          STEP 2: MARK EPISODES AS UNRELEASED               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "ℹ WHAT THIS DOES:"
echo "  • Changes episode state to 'Unreleased'"
echo "  • Tells Riven these episodes are not yet available/aired"
echo "  • Riven will SKIP these episodes during scraping"
echo "  • Episodes remain in the database (not deleted)"
echo ""
echo "WHEN TO USE THIS:"
echo "  • Mark future episodes that haven't aired yet"
echo "  • Temporarily disable specific episodes from being searched"
echo "  • Useful for shows with irregular release schedules"
echo ""
read -p "Do you want to mark specific episodes as 'Unreleased'? (y/n): " do_unreleased

if [[ "$do_unreleased" =~ ^[Yy](es)?$ ]]; then
    read -p "Enter Season Number: " target_season
    echo ""
    echo "Enter Episode Number(s):"
    echo "  • For specific episodes: 1,2,3"
    echo "  • For ALL episodes in the season: type 'A' or 'All'"
    echo ""
    read -p "Episode Number(s): " target_eps

    # Handle 'A', 'a', or 'All'
    if [[ "${target_eps,,}" =~ ^a(ll)?$ ]]; then
        ep_condition="s.number = $target_season"
        echo ""
        echo "Marking ALL episodes in Season $target_season as Unreleased..."
    else
        ep_condition="s.number = $target_season AND e.number IN ($target_eps)"
        echo ""
        echo "Marking episodes $target_eps in Season $target_season as Unreleased..."
    fi

    docker exec riven-db psql -U postgres -d riven -c "
    UPDATE \"MediaItem\" SET last_state = 'Unreleased'
    WHERE id IN (
        SELECT mi.id FROM \"MediaItem\" mi
        INNER JOIN \"Episode\" e ON mi.id = e.id
        INNER JOIN \"Season\" s ON e.parent_id = s.id
        WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id)
        AND $ep_condition
    );"
    echo "✓ Episodes set to Unreleased."
else
    echo "ℹ Skipping unreleased marking step."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         STEP 3: RESET SEASON(S) TO INDEXED                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "ℹ WHAT THIS DOES:"
echo "  • Resets ALL episodes in selected season(s) to 'Indexed' state"
echo "  • Also resets the season itself to 'Indexed'"
echo "  • Clears scraping history (scraped_at, scraped_times, active_stream)"
echo "  • Tells Riven to start fresh and re-scrape these episodes"
echo ""
echo "WHEN TO USE THIS:"
echo "  • Force Riven to re-search for better quality streams"
echo "  • Reset after changing scraper settings"
echo "  • Clear 'Unknown' or 'Failed' states and try again"
echo "  • Start over with specific seasons"
echo ""
read -p "Do you want to reset entire season(s) to 'Indexed'? (y/n): " do_reset

if [[ "$do_reset" =~ ^[Yy](es)?$ ]]; then
    echo ""
    echo "Enter Season Number(s):"
    echo "  • For specific seasons: 1,2,3"
    echo "  • For ALL seasons: type 'A' or 'All'"
    echo ""
    read -p "Season Number(s): " reset_seasons

    # Handle 'A', 'a', or 'All'
    if [[ "${reset_seasons,,}" =~ ^a(ll)?$ ]]; then
        echo ""
        echo "Resetting ALL episodes and seasons to 'Indexed'..."
        
        # Reset all episodes to Indexed
        docker exec riven-db psql -U postgres -d riven -c "
        UPDATE \"MediaItem\" 
        SET last_state = 'Indexed',
            scraped_at = NULL,
            scraped_times = 0,
            active_stream = NULL
        WHERE id IN (
            SELECT mi.id FROM \"MediaItem\" mi
            INNER JOIN \"Episode\" e ON mi.id = e.id
            INNER JOIN \"Season\" s ON e.parent_id = s.id
            WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id)
        );"

        # Reset all seasons to Indexed
        docker exec riven-db psql -U postgres -d riven -c "
        UPDATE \"MediaItem\" 
        SET last_state = 'Indexed',
            scraped_at = NULL,
            scraped_times = 0,
            active_stream = NULL
        WHERE type = 'season' AND id IN (
            SELECT s.id FROM \"Season\" s
            WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id)
        );"

        echo "✓ All episodes and seasons reset to 'Indexed'."
    else
        echo ""
        echo "Resetting Season(s) $reset_seasons to 'Indexed'..."
        
        # Reset episodes in specified seasons to Indexed
        docker exec riven-db psql -U postgres -d riven -c "
        UPDATE \"MediaItem\" 
        SET last_state = 'Indexed',
            scraped_at = NULL,
            scraped_times = 0,
            active_stream = NULL
        WHERE id IN (
            SELECT mi.id FROM \"MediaItem\" mi
            INNER JOIN \"Episode\" e ON mi.id = e.id
            INNER JOIN \"Season\" s ON e.parent_id = s.id
            WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id)
            AND s.number IN ($reset_seasons)
        );"

        # Reset specified seasons to Indexed
        docker exec riven-db psql -U postgres -d riven -c "
        UPDATE \"MediaItem\" 
        SET last_state = 'Indexed',
            scraped_at = NULL,
            scraped_times = 0,
            active_stream = NULL
        WHERE type = 'season' AND id IN (
            SELECT s.id FROM \"Season\" s
            WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id)
            AND s.number IN ($reset_seasons)
        );"

        echo "✓ Season(s) $reset_seasons and their episodes reset to 'Indexed'."
    fi
else
    echo "ℹ Skipping season reset step."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            STEP 4: UPDATE SEASON STATES                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "ℹ WHAT THIS DOES:"
echo "  • Sets the state for entire season(s)"
echo "  • Affects how Riven treats the season during updates"
echo ""
echo "STATE MEANINGS:"
echo "  • Completed: All episodes are done, stop checking for new ones"
echo "  • Ongoing: Season is airing, keep checking for new episodes"
echo "  • Unreleased: Season hasn't aired yet, skip for now"
echo "  • PartiallyCompleted: Some episodes done, still working on others"
echo "  • Indexed: Ready to be scraped/processed"
echo "  • Scraped: Has been scraped, ready for download"
echo "  • Paused: Temporarily stop processing this season"
echo ""

if [ $deleted_count -gt 0 ]; then
    echo "You deleted episodes in Season(s): $affected_seasons"
    echo "Choose a state for these affected seasons:"
    echo ""
    echo "  1) Completed"
    echo "  2) Ongoing"
    echo "  3) Unreleased"
    echo "  4) PartiallyCompleted"
    echo "  5) Indexed"
    echo "  6) Scraped"
    echo "  7) Paused"
    echo ""
    read -p "Choice (1-7): " del_ms_choice
    case $del_ms_choice in
        1) ms_state="Completed" ;;
        2) ms_state="Ongoing" ;;
        3) ms_state="Unreleased" ;;
        4) ms_state="PartiallyCompleted" ;;
        5) ms_state="Indexed" ;;
        6) ms_state="Scraped" ;;
        7) ms_state="Paused" ;;
    esac
    if [ ! -z "$ms_state" ]; then
        docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = '$ms_state' WHERE type = 'season' AND id IN (SELECT s.id FROM \"Season\" s WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id) AND s.number IN ($affected_seasons));"
        echo "✓ Seasons $affected_seasons updated to $ms_state."
    fi
else
    read -p "Update states for any seasons? Enter season numbers (e.g. 1,2) or press Enter to skip: " manual_seasons
    if [ ! -z "$manual_seasons" ]; then
        echo ""
        echo "Choose state for Season(s) $manual_seasons:"
        echo ""
        echo "  1) Completed"
        echo "  2) Ongoing"
        echo "  3) Unreleased"
        echo "  4) PartiallyCompleted"
        echo "  5) Indexed"
        echo "  6) Scraped"
        echo "  7) Paused"
        echo ""
        read -p "Choice (1-7): " ms_choice
        case $ms_choice in
            1) ms_state="Completed" ;;
            2) ms_state="Ongoing" ;;
            3) ms_state="Unreleased" ;;
            4) ms_state="PartiallyCompleted" ;;
            5) ms_state="Indexed" ;;
            6) ms_state="Scraped" ;;
            7) ms_state="Paused" ;;
        esac
        if [ ! -z "$ms_state" ]; then
            docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = '$ms_state' WHERE type = 'season' AND id IN (SELECT s.id FROM \"Season\" s WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id) AND s.number IN ($manual_seasons));"
            echo "✓ Seasons $manual_seasons updated to $ms_state."
        fi
    else
        echo "ℹ Skipping manual season state update."
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             STEP 5: UPDATE SHOW STATE                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "ℹ WHAT THIS DOES:"
echo "  • Sets the state for THE ENTIRE SHOW"
echo "  • Affects how Riven monitors and updates this show"
echo ""
echo "STATE MEANINGS:"
echo "  • Completed: Show is finished, no new episodes expected"
echo "  • Ongoing: Show is actively airing, check for new episodes"
echo "  • Indexed: Show is ready to be processed/scraped"
echo "  • Unreleased: Show hasn't premiered yet"
echo "  • PartiallyCompleted: Some seasons done, others ongoing"
echo ""
echo "Choose state for THE ENTIRE SHOW: $show_title"
echo ""
echo "  1) Completed"
echo "  2) Ongoing"
echo "  3) Indexed"
echo "  4) Unreleased"
echo "  5) PartiallyCompleted"
echo ""
read -p "Choice (1-5 or press Enter to skip): " show_choice

case $show_choice in
    1) 
        docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = 'Completed' WHERE id = $show_id;"
        echo "✓ Show set to 'Completed'."
        ;;
    2) 
        docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = 'Ongoing' WHERE id = $show_id;"
        echo "✓ Show set to 'Ongoing'."
        ;;
    3) 
        docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = 'Indexed' WHERE id = $show_id;"
        echo "✓ Show set to 'Indexed'."
        ;;
    4) 
        docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = 'Unreleased' WHERE id = $show_id;"
        echo "✓ Show set to 'Unreleased'."
        ;;
    5) 
        docker exec riven-db psql -U postgres -d riven -c "UPDATE \"MediaItem\" SET last_state = 'PartiallyCompleted' WHERE id = $show_id;"
        echo "✓ Show set to 'PartiallyCompleted'."
        ;;
    *)
        echo "ℹ Skipping show state update."
        ;;
esac

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              FINAL VERIFICATION                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Show State:"
echo "───────────"
docker exec riven-db psql -U postgres -d riven -c "SELECT title, last_state FROM \"MediaItem\" WHERE id = $show_id;"

echo ""
echo "Season States:"
echo "──────────────"
docker exec riven-db psql -U postgres -d riven -c "SELECT s.number as season, mi.last_state FROM \"Season\" s INNER JOIN \"MediaItem\" mi ON s.id = mi.id WHERE s.parent_id = (SELECT id FROM \"Show\" WHERE id = $show_id) ORDER BY s.number;"

echo ""
echo "Episode State Summary:"
echo "──────────────────────"
docker exec riven-db psql -U postgres -d riven -c "
SELECT mi.last_state AS state, COUNT(*) AS count
FROM \"MediaItem\" mi
INNER JOIN \"Episode\" e ON mi.id = e.id
INNER JOIN \"Season\" s ON e.parent_id = s.id
INNER JOIN \"Show\" sh ON s.parent_id = sh.id
INNER JOIN \"MediaItem\" parent ON sh.id = parent.id
WHERE $final_condition
GROUP BY mi.last_state
ORDER BY mi.last_state;"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                 SCRIPT COMPLETED!                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
    echo "ℹ Your database backup is located at: /tmp/riven_backup.sql"
    echo ""
fi
echo "Done."