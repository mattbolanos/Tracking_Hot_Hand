# --- Plot Functions --- #

# ------------------ #
# --- Shot chart --- #
# ------------------ #

# Calc hex bounds
hex_bounds <- function(x, binwidth) {
  c(
    plyr::round_any(min(x), binwidth, floor) - 1e-6,
    plyr::round_any(max(x), binwidth, ceiling) + 1e-6
  )
}

# Calculate hex bins for shot chart
get_hexbin_data <- function(type = "League Avg", player_shots, comparison_shots) {
  
  # If comparing to league average
  if (type == "League Avg"){
    
    # --- Calculate bounds of hexagons
    xbnds <- hex_bounds(player_shots$loc_x, 1.5)
    xbins <- diff(xbnds) / 1.5
    ybnds <- hex_bounds(player_shots$loc_y, 1.5)
    ybins <- diff(ybnds) / 1.5
    
    # Hex bin class
    hb <- hexbin(
      x = player_shots$loc_x,
      y = player_shots$loc_y,
      xbins = xbins,
      xbnds = xbnds,
      ybnds = ybnds,
      shape = ybins / xbins,
      IDs = TRUE
    )
    
    # Add hex bin ID
    player_shots <- player_shots %>%
      mutate(
        hexbin_id = hb@cID
      )
    
    # PPS/Points Scored/FG% by hex bin ID
    hexbin_stats <- player_shots %>%
      group_by(
        hexbin_id
      ) %>%
      summarise(
        hex_attempts = n(),
        threes = sum(shot_value == 3 & shot_made_numeric == 1),
        hex_pct = (sum(shot_made_numeric) + (threes * .5)) / hex_attempts,
        hex_points_scored = sum(shot_made_numeric * shot_value),
        hex_points_per_shot = sum(shot_made_numeric * shot_value) / hex_attempts,
        .groups = "drop"
      )
    
    # Get max attempts by hex bin ID / zone
    hexbin_ids_to_zones <- player_shots %>%
      group_by(
        hexbin_id, zone_range, name_zone
      ) %>%
      summarise(
        attempts = n(),
        .groups = "drop"
      ) %>%
      # Take most attempts for each hex bin ID
      group_by(
        hexbin_id
      ) %>%
      slice_max(
        attempts, n = 1, with_ties = F
      ) %>%
      ungroup() %>%
      select(
        hexbin_id, zone_range, name_zone
      )
    
    # Join together
    hexbin_stats <- hexbin_stats %>%
      inner_join(
        hexbin_ids_to_zones,
        by = "hexbin_id"
      )
    
    # --- Calculate center coordinates of hex bins
    sx <- hb@xbins / diff(hb@xbnds)
    sy <- (hb@xbins * hb@shape) / diff(hb@ybnds)
    dx <- 1 / (2 * sx)
    dy <- 1 / (2 * sqrt(3) * sy)
    origin_coords <- hexcoords(dx, dy)
    
    hex_centers <- hcell2xy(hb)
    
    hexbin_coords <- bind_rows(lapply(1:hb@ncells, function(i) {
      data.frame(
        x = origin_coords$x + hex_centers$x[i],
        y = origin_coords$y + hex_centers$y[i],
        center_x = hex_centers$x[i],
        center_y = hex_centers$y[i],
        hexbin_id = hb@cell[i]
      )
    }))
    
    # Join to hexbin stats
    hexbin_coords <- hexbin_coords %>%
      inner_join(
        hexbin_stats,
        by = "hexbin_id"
      )
    
    # PPS/Points Scored/FG% by zone
    zone_stats <- player_shots %>%
      group_by(
        zone_range, name_zone
      ) %>%
      summarise(
        zone_attempts = n(),
        threes = sum(shot_value == 3 & shot_made_numeric == 1),
        zone_pct = (sum(shot_made_numeric) + (threes * .5)) / zone_attempts,
        zone_points_scored = sum(shot_made_numeric * shot_value),
        zone_points_per_shot = sum(shot_made_numeric * shot_value) / zone_attempts,
        .groups = "drop"
      )
    
    # Join coordinates to stats
    hex_data <- hexbin_coords %>%
      inner_join(
        zone_stats,
        by = c("zone_range", "name_zone")
      ) %>%
      inner_join(
        comparison_shots,
        by = c("zone_range", "name_zone")
      ) %>%
      # Adjust hex bin x-y, and calculate player stats - league average
      mutate(
        radius_factor = .25 + (1 - .25) * log(hex_attempts + 1) / log(max(.$hex_attempts) + 1),
        adj_x = center_x + radius_factor * (x - center_x),
        adj_y = center_y + radius_factor * (y - center_y),
        bounded_fg_diff = pmin(pmax(zone_pct - league_pct, -.15), .15),
        bounded_fg_pct = pmin(pmax(zone_pct, .2), .7),
        bounded_points_per_shot = pmin(pmax(zone_points_per_shot, .5), 1.5),
        adj_x = adj_x*-1
      )
    
    return(hex_data)
    
  }else{
    
    ## If comparing to own average ##
    
    # Player base averages
    player_zone_stats <- player_shots %>%
      group_by(
        zone_range, name_zone
      ) %>%
      summarise(
        threes = sum(shot_value == 3 & shot_made_numeric == 1),
        league_pct = (sum(shot_made_numeric) + (threes * .5)) / n(),
        league_pps = sum(shot_made_numeric * shot_value) / sum(shot_attempted_flag),
        max_dist = max(distance_shot),
        .groups = 'drop'
      )
    # --- Calculate bounds of hexagons
    xbnds <- hex_bounds(comparison_shots$loc_x, 1.5)
    xbins <- diff(xbnds) / 1.5
    ybnds <- hex_bounds(comparison_shots$loc_y, 1.5)
    ybins <- diff(ybnds) / 1.5
    
    # Hex bin class
    hb <- hexbin(
      x = comparison_shots$loc_x,
      y = comparison_shots$loc_y,
      xbins = xbins,
      xbnds = xbnds,
      ybnds = ybnds,
      shape = ybins / xbins,
      IDs = TRUE
    )
    
    # Add hex bin ID to shots
    comparison_shots <- comparison_shots %>%
      mutate(hexbin_id = hb@cID)
    
    # PPS/Points Scored/FG% by hex bin ID
    hexbin_stats <- comparison_shots %>%
      group_by(
        hexbin_id
      ) %>%
      summarise(
        hex_attempts = n(),
        threes = sum(shot_value == 3 & shot_made_numeric == 1),
        hex_pct = (sum(shot_made_numeric) + (threes * .5)) / hex_attempts,
        hex_points_scored = sum(shot_made_numeric * shot_value),
        hex_points_per_shot = sum(shot_made_numeric * shot_value) / hex_attempts,
        .groups = "drop"
      )
    
    # Get max attempts by hex bin ID / zone
    hexbin_ids_to_zones <- comparison_shots %>%
      group_by(
        hexbin_id, zone_range, name_zone
      ) %>%
      summarise(
        attempts = n(),
        .groups = "drop"
      ) %>%
      # Take most attempts for each hex bin ID
      group_by(
        hexbin_id
      ) %>%
      slice_max(
        attempts, n = 1, with_ties = F
      ) %>%
      ungroup() %>%
      select(
        hexbin_id, zone_range, name_zone
      )
    
    # Join together
    hexbin_stats <- hexbin_stats %>%
      inner_join(
        hexbin_ids_to_zones,
        by = "hexbin_id"
      )
    
    # --- Calculate center coordinates of hex bins
    sx <- hb@xbins / diff(hb@xbnds)
    sy <- (hb@xbins * hb@shape) / diff(hb@ybnds)
    dx <- 1 / (2 * sx)
    dy <- 1 / (2 * sqrt(3) * sy)
    origin_coords <- hexcoords(dx, dy)
    
    hex_centers <- hcell2xy(hb)
    
    hexbin_coords <- bind_rows(lapply(1:hb@ncells, function(i) {
      data.frame(
        x = origin_coords$x + hex_centers$x[i],
        y = origin_coords$y + hex_centers$y[i],
        center_x = hex_centers$x[i],
        center_y = hex_centers$y[i],
        hexbin_id = hb@cell[i]
      )
    }))
    
    hexbin_coords <- hexbin_coords %>%
      inner_join(
        hexbin_stats,
        by = "hexbin_id"
      )
    
    # PPS/Points Scored/FG% by zone
    zone_stats <- comparison_shots %>%
      group_by(
        zone_range, name_zone
      ) %>%
      summarise(
        zone_attempts = n(),
        threes = sum(shot_value == 3 & shot_made_numeric == 1),
        zone_pct = (sum(shot_made_numeric) + (threes * .5)) / zone_attempts,
        zone_points_scored = sum(shot_made_numeric * shot_value),
        zone_points_per_shot = sum(shot_made_numeric * shot_value) / zone_attempts,
        .groups = "drop"
      )
    
    # Join coordinates to stats
    hex_data <- hexbin_coords %>%
      inner_join(
        zone_stats,
        by = c("zone_range", "name_zone")
      ) %>%
      inner_join(
        player_zone_stats %>% select(-c(max_dist, league_pps)),
        by = c("zone_range", "name_zone")
      ) %>%
      # Adjust hex bin x-y, and calculate player stats - league average
      mutate(
        radius_factor = .25 + (1 - .25) * log(hex_attempts + 1) / log(max(.$hex_attempts) + 1),
        adj_x = center_x + radius_factor * (x - center_x),
        adj_y = center_y + radius_factor * (y - center_y),
        bounded_fg_diff = pmin(pmax(zone_pct - league_pct, -.15), .15),
        bounded_fg_pct = pmin(pmax(zone_pct, .2), .7),
        bounded_points_per_shot = pmin(pmax(zone_points_per_shot, .5), 1.5),
        adj_x = adj_x*-1
      )
    
    return(hex_data)
  }
  
}

# Plot shot chart
plot_shot_chart <- function(hex_df, type = "League Avg", streak_sel, year_sel, player_sel) {
  
  headshot_url <- players %>%
    filter(
      namePlayer == player_sel
    ) %>%
    pull(urlPlayerHeadshot)
  
  # Download headshot
  t <- tempfile()
  download.file(headshot_url, t, mode = "wb")
  pic <- readPNG(t)
  
  if (type == "League Avg"){
    
    legend_title <- paste0("eFG% vs. League Average After ", streak_sel)
    
  }else{
    
    # Get first name
    first_name <- paste0(word(player_sel, 1))
    
    first_name_ins <- paste0(
      first_name,
      ifelse(substr(first_name, nchar(first_name), nchar(first_name)) == "s", "'", "'s")
    )
    
    legend_title <- paste("eFG% vs.", first_name_ins, "Base Zone Average")
    
  }
  # Set court theme
  court_theme <- light_court_theme$light
  
  
  p <- ggplot() +
    geom_polygon(
      data = hex_df,
      aes(
        x = adj_x,
        y = adj_y,
        group = hexbin_id, 
        fill = bounded_fg_diff, 
        color = after_scale(clr_darken(fill, .25))
      ),
      size = .5
    ) + 
    scale_x_continuous(
      limits = c(-27.5, 27.5)
    ) + 
    scale_y_continuous(
      limits = c(0, 62)
    ) +
    scale_linetype_identity() +
    scale_fill_distiller(
      direction = -1, 
      palette = "RdBu", 
      limits = c(-.15, .15), 
      breaks = seq(-.15, .15, .03),
      labels = c("-15%", "-12%", "-9%", "-6%", "-3%", "0%", "+3%", "+6%", "+9%", "+12%", "+15%"),
      legend_title
    ) +
    guides(
      fill = guide_legend(
        label.position = 'bottom', 
        title.position = 'top', 
        default.unit="inch", 
        title.hjust = .5,
        title.vjust = 0,
        label.vjust = 3,
        nrow = 1
      )
    )+
    labs(
      title = paste0(player_sel, " After ", streak_sel),
      subtitle = paste0(year_sel, " Regular Season"),
      caption = ("Chart: @mattabolanos | Data: NBA Stats API")
    )+
    geom_path(
      data = court_points,
      aes(x = x, y = y, group = desc, linetype = dash),
      color = court_theme$lines
    ) +
    coord_fixed(
      ylim = c(0, 48), xlim = c(-25, 25), clip = "off"
    ) +
    theme(
      plot.background = element_rect(fill = '#FFFCF7', color = '#FFFCF7'),
      panel.background = element_rect(fill = '#FFFCF7', color = '#FFFCF7'),
      panel.grid = element_blank(),
      legend.background = element_rect(fill = '#FFFCF7', color = '#FFFCF7'),
      legend.key.width = unit(.08, "npc"),
      legend.key.height = unit(.03, "npc"),
      line = element_blank(),
      axis.title.x = element_blank(),
      axis.title.y = element_blank(),
      axis.text.x = element_blank(),
      axis.text.y = element_blank(),
      text=element_text(size=11,  family= "Georgia", color = court_theme$text),
      legend.spacing.x = unit(0, "npc"), 
      legend.title=element_text(size=13, face = "bold.italic"),
      legend.text = element_text(size = 10.5, face = "bold"), 
      legend.margin= margin(t = -.065, unit = 'npc'),
      plot.margin = margin(unit = "npc", t = .02, b = .02, r = .02, l = .02),
      legend.position = 'bottom',
      # legend.box.margin = leg_box_mar, 
      plot.title = element_text(hjust = 0.5, size = 18, face = "bold", vjust = -2),
      plot.subtitle = element_text(hjust = 0.5, size = 15, vjust = -2.5, face = "italic", margin = margin(b = -.25, unit = "npc")), 
      plot.caption = element_text(hjust = 0.5, size = 10, vjust = 2.5)
    )
  
  # Add headshot
  fin <- ggdraw(p)+
    theme(
      plot.background = element_rect(fill="#FFFCF7", color = NA),
      panel.border = element_rect(colour = "#232323", fill=NA, size = 1 )
      
    ) +
    annotation_custom(
      rasterGrob(pic, width = unit(.1285,'npc'), x = .067, y = .94, default.units = "npc")
    )
  
  ggsave("shot_chart.png", fin, h = 7.75, w = 8)
  
}

# Plot empty data
plot_empty <- function(streak_sel, year_sel, player_sel)  {
  
  headshot_url <- players %>%
    filter(
      namePlayer == player_sel
    ) %>%
    pull(urlPlayerHeadshot)
  
  # Download headshot
  t <- tempfile()
  download.file(headshot_url, t, mode = "wb")
  pic <- readPNG(t)
  
  # Set court theme
  court_theme <- light_court_theme$light
  
  # Empty plot
  p <- ggplot() +
    scale_x_continuous(
      limits = c(-27.5, 27.5)
    ) + 
    scale_y_continuous(
      limits = c(0, 62)
    ) +
    scale_linetype_identity() +
    guides(
      fill = guide_legend(
        label.position = 'bottom', 
        title.position = 'top', 
        default.unit="inch", 
        title.hjust = .5,
        title.vjust = 0,
        label.vjust = 3,
        nrow = 1
      )
    ) +
    labs(
      title = paste0(player_sel, " After ", streak_sel),
      subtitle = paste0(year_sel, " Regular Season")
    ) +
    geom_path(
      data = court_points,
      aes(x = x, y = y, group = desc, linetype = dash),
      color = court_theme$lines
    ) +
    coord_fixed(
      ylim = c(0, 48), xlim = c(-25, 25)
    ) +
    geom_text(
      aes(x = 0, y = 38, label = "No Shots Found - Try a Different Filter!"),
      size = 6.5
    ) +
    theme(
      plot.background = element_rect(fill = '#FFFCF7', color = '#FFFCF7'),
      panel.background = element_rect(fill = '#FFFCF7', color = '#FFFCF7'),
      panel.grid = element_blank(),
      legend.background = element_rect(fill = '#FFFCF7', color = '#FFFCF7'),
      legend.key.width = unit(.05, "npc"),
      legend.key.height = unit(.03, "npc"),
      line = element_blank(),
      axis.title.x = element_blank(),
      axis.title.y = element_blank(),
      axis.text.x = element_blank(),
      axis.text.y = element_blank(),
      text=element_text(size=11,  family= "Georgia", color = court_theme$text),
      legend.spacing.x = unit(0, "npc"), 
      legend.title=element_text(size=13, face = "bold.italic"),
      legend.text = element_text(size = 9), 
      legend.margin= margin(t = -.065, unit = 'npc'),
      plot.margin = margin(unit = "npc"),
      legend.position = 'bottom',
      # legend.box.margin = leg_box_mar, 
      plot.title = element_text(hjust = 0.5, size = 16, face = "bold", vjust = -2),
      plot.subtitle = element_text(hjust = 0.5, size = 14, vjust = -2.5, face = "italic", margin = margin(b = -.25, unit = "npc")), 
      plot.caption = element_text(hjust = 0.5, size = 8.5, vjust = 2.5)
    )
  
  # Add headshot
  fin <- ggdraw(p)+
    theme(
      plot.background = element_rect(fill="#FFFCF7", color = NA),
      panel.border = element_rect(colour = "#232323", fill=NA, size = 1 )
      
    ) +
    annotation_custom(
      rasterGrob(pic, width = unit(.13,'npc'), x = .067, y = .949, default.units = "npc")
    )
  
  ggsave("shot_chart.png", fin, h = 7.75, w = 8)
  
}

# --------------------- #
# --- Summary table --- #
# --------------------- #

# Summary table
shot_sum_table <- function(base_pct_df, streak_pct_df, type = "Compared to League Average", streak_sel) {
  
  # Construct summary df
  zone_sum <- streak_pct_df %>%
    # Only take zones present in both
    inner_join(
      base_pct_df,
      by = c("zone_range", "name_zone")
    ) %>% 
    mutate(
      fg_diff = streak_pct - base_pct,
      across(
        .cols = c(
          streak_pct, streak_pps, fg_diff
        ),
        ~ round(.x, 3)
      ),
      name_zone = gsub("Side", "", name_zone)
    ) %>%
    # Don't need back court shots
    filter(
      name_zone != "Back Court"
    ) %>% 
    replace(
      is.na(.), 0
    ) %>% 
    mutate(
      # Calculate color references
      max_att = max(streak_fga, na.rm = TRUE),
      max_pps = ifelse(max(streak_pps, na.rm = TRUE) > 1.7, max(streak_pps, na.rm = TRUE), 1.7),
      max_pct = ifelse(max(streak_pct, na.rm = TRUE) > .7, max(streak_pct, na.rm = TRUE), .7),
      col_streak_pct = get_color(streak_pct / max_pct),
      col_streak_pps = get_color(streak_pps / max_pps),
      col_streak_fga = get_color(streak_fga / max_att),
      icon_fg_diff = ifelse(
        fg_diff < 0,
        "https://images.emojiterra.com/google/android-10/512px/1f9ca.png",
        "https://images.emojiterra.com/google/android-11/512px/1f525.png"
      ),
      # Adjust zone_range for sorting
      zone_range = case_when(
        zone_range == "Less Than 8 ft." ~ 7,
        zone_range == "24+ ft." ~ 24,
        TRUE ~ as.numeric(str_split(zone_range, pattern = "-", simplify = T, n = 2)[,1])
      )
    ) %>%
    select(
      zone_range, name_zone, streak_pct, streak_pps, streak_fga, fg_diff, starts_with("col_"), icon_fg_diff
    ) %>% 
    suppressWarnings() %>% 
    arrange(
      desc(streak_fga)
    )
  
  # Set last column title
  if (type == "Compared to League Average"){
    
    col_title <- "&Delta; Lg Avg Zone eFG%"
    
    tool_tip <- "Player's eFG% &minus; Lg Avg Zone eFG% after"
    
  }else{
    
    col_title <- "&Delta; Player Zone eFG%"
    
    tool_tip <- "Player's eFG% &minus; Player Avg Zone eFG% after" 
    
  }
  
  # Create reactable
  zone_sum %>% 
    reactable(
      compact = TRUE,
      language = reactableLang(
        noData = "No Shots Found"
      ),
      defaultPageSize = 15,
      columnGroups = list(
        colGroup(name = "Shot Zone", columns = c("zone_range", "name_zone")),
        colGroup(name = "Zone Stats", columns = c("streak_pct", "streak_pps", "fg_diff", "streak_fga"))
      ),
      theme = reactableTheme(
        headerStyle = list(
          "&:hover[aria-sort]" = list(background = "hsl(0, 0%, 96%)"),
          "&[aria-sort='ascending'], &[aria-sort='descending']" = list(background = "hsl(0, 0%, 96%)"),
          borderColor = "#555"
        )
      ),
      striped = FALSE,
      borderless = TRUE,
      showSortIcon = TRUE,
      searchable = FALSE,
      defaultColDef = colDef(
        style = cell_style(font_weight = 500)
      ),
      style = list(fontFamily = "Karla"),
      columns = list(
        zone_range = colDef(
          name = "Distance",
          maxWidth = 90,
          align = "center",
          cell = function(x){
            
            if (x == 7){
              
              val <- "< 8 ft."
              
            }
            
            if (x %in% c(8, 16)){
              
              val <- paste0(x, "-", x + 8, " ft.")
              
            }
            
            if (x == 24){
              
              val <- "24+ ft."
              
            }
            
            val
            
          },
          style = cell_style(font_weight = "bold", font_style = "italic")
        ),
        name_zone = colDef(
          name = "Area",
          maxWidth = 100,
          align = "center",
          style = cell_style(font_weight = "bold", font_style = "italic")
        ),
        streak_pct = colDef(
          name = "Streak eFG%",
          maxWidth = 115,
          align = "center",
          header = with_tooltip(
            "Streak eFG%", 
            paste("The player's effective field goal % after", streak_sel)
          ),
          format = colFormat(percent = TRUE, digits = 1),
          style = color_scales(
            zone_sum,
            color_ref = "col_streak_pct"
          )
        ),
        streak_pps = colDef(
          name = "Streak PPS",
          maxWidth = 105,
          align = "center",
          header = with_tooltip(
            "Streak PPS", 
            paste("Player's points per shot after", streak_sel)
          ),
          format = colFormat(digits = 2),
          style = color_scales(
            zone_sum,
            color_ref = "col_streak_pps"
          )
        ),
        streak_fga = colDef(
          name = "Streak FGA",
          maxWidth = 105,
          align = "center",
          header = with_tooltip(
            "Streak FGA", 
            paste("Total field goals attempted by the player after", streak_sel)
          ),
          style = color_scales(
            zone_sum,
            color_ref = "col_streak_fga"
          )
        ),
        fg_diff = colDef(
          name = col_title,
          width = 175,
          html = T,
          align = 'center',
          header = with_tooltip(
            col_title, 
            paste(tool_tip, streak_sel)
          ),
          cell = data_bars(
            ., 
            fill_color = c("lightblue", "orange"),
            number_fmt = scales::percent_format(accuracy = .1),
            bold_text = TRUE,
            img_ref = "icon_fg_diff",
            border_width = "thick",
            min_value = -1,
            max_value = 1,
            bar_height = 20,
            text_size = 13
          ),
          style = list(borderLeft = "1px dashed rgba(0, 0, 0, 0.3)")
        ),
        # Don't need to show colors and icon references
        col_streak_pct = colDef(show = FALSE),
        col_streak_pps = colDef(show = FALSE),
        col_streak_fga = colDef(show = FALSE),
        icon_fg_diff = colDef(show = FALSE)
      )
    )
}

# -------------------------- #
# --- Def distance table --- #
# -------------------------- #

# Custom range input filter with label and value
rangeFilter <- function(tableId, columnId, label, min, max, value = NULL, step = NULL, width = "250px") {
  
  value <- if (!is.null(value)) value else min
  inputId <- sprintf("filter_%s_%s", tableId, columnId)
  valueId <- sprintf("filter_%s_%s__value", tableId, columnId)
  oninput <- paste(
    sprintf("document.getElementById('%s').textContent = this.value;", valueId),
    sprintf("Reactable.setFilter('%s', '%s', this.value)", tableId, columnId)
  )
  
  div(
    tags$p(`for` = inputId, label, class = "slider-label"),
    div(
      style = sprintf("display: flex; align-items: center; width: %s", validateCssUnit(width)),
      tags$input(
        id = inputId,
        type = "range",
        min = min,
        max = max,
        step = step,
        value = value,
        oninput = oninput,
        onchange = oninput, # For IE11 support
        style = "width: 100%;"
      ),
      span(id = valueId, style = "margin-left: 8px;", value)
    )
  )
}

# Filter method that filters numeric columns by minimum value
filterMinValue <- JS("function(rows, columnId, filterValue) {
  return rows.filter(function(row) {
    return row.values[columnId] >= filterValue
  })
}")

# Summary defender distance table
def_distance_table <- function(shot_df, streak_sel) {
  
  # Calculate general streak statistics
  general_streak <- shot_df %>% 
    group_by(
      shooter 
    ) %>% 
    summarise(
      streak_fga = n(),
      threes = sum(shot_value == 3 & is_shot_made),
      streak_efg = (sum(is_shot_made) + (threes * .5)) / streak_fga,
      pct_open = sum(def_dist == "Open") / n(),
      .groups = "drop"
    ) %>% 
    select(
      -threes
    )
  
  # Calculate by defender distance bin
  combined_dat <- shot_df %>% 
    group_by(
      shooter, def_dist
    ) %>% 
    summarise(
      fga = n(),
      threes = sum(shot_value == 3 & is_shot_made),
      efg = (sum(is_shot_made) + (threes * .5)) / fga,
      .groups = "drop"
    ) %>% 
    # Pivot out to get one row per shooter
    pivot_wider(
      id_cols = shooter,
      values_from = efg,
      names_from = def_dist,
      names_prefix = "efg_"
    ) %>% 
    clean_names() %>% 
    # Replace NAs w/ 0
    replace_na(
      list(efg_open = 0, efg_tight = 0)
    ) %>% 
    mutate(
      # Calculate coverage diff
      coverage_diff = efg_tight - efg_open
    ) %>% 
    # Join general stats
    left_join(
      general_streak,
      by = "shooter"
    ) %>% 
    # Join bsae eFG%s
    left_join(
      base_efgs,
      by = "shooter"
    ) %>% 
    mutate(
      # Round
      across(
        .cols = where(is.numeric),
        ~ round(.x, 3)
      )
    ) %>% 
    # Join headshot urls
    left_join(
      players %>% select(shooter = namePlayer, headshot = urlPlayerHeadshot),
      by = "shooter"
    ) %>%
    # Create color referemces
    mutate(
      col_fga = get_color(streak_fga / max(streak_fga, na.rm = TRUE)),
      col_efg = get_color(streak_efg / max(streak_efg, na.rm = TRUE)),
      col_base = get_color(base_efg / max(base_efg, na.rm = TRUE)),
      col_pct = get_color(pct_open),
      col_open = get_color(efg_open / max(efg_open, na.rm = TRUE)),
      col_tight = get_color(efg_tight / max(efg_tight, na.rm = TRUE)),
      icon_fg_diff = ifelse(
        coverage_diff < 0,
        "https://images.emojiterra.com/google/android-10/512px/1f9ca.png",
        "https://images.emojiterra.com/google/android-11/512px/1f525.png"
      ),
      headshot = paste0(
        "<img src='", headshot,"' height='", 40 / (260/190), "'>"
      )
    ) %>% 
    select(
      headshot, shooter, streak_fga, streak_efg, base_efg, pct_open, efg_open, efg_tight, coverage_diff,
      starts_with("col_"), icon_fg_diff
    )
  
  # Reactable
  combined_dat %>% 
    arrange(
      desc(streak_fga)
    ) %>% 
    reactable(
      elementId = "def-table-range",
      fullWidth = FALSE,
      language = reactableLang(
        noData = "No Shots Found"
      ),
      columnGroups = list(
        colGroup(
          name = "Player",
          columns = c("shooter", "headshot")
        )
      ),
      defaultPageSize = 10,
      class = "defender-table",
      striped = FALSE,
      borderless = TRUE,
      showSortIcon = TRUE,
      resizable = TRUE,
      bordered = FALSE,
      searchable = TRUE,
      defaultColDef = colDef(
        style = cell_style(font_weight = 500),
        align = "center"
      ),
      style = list(fontFamily = "Karla"),
      columns = list(
        headshot = colDef(
          name = "",
          width = 50,
          align = 'center',
          html = TRUE
        ),
        shooter = colDef(
          name = "",
          align = "left",
          style = cell_style(horizontal_align = "left"),
          width = 190
        ),
        streak_fga = colDef(
          name = "Streak FGA",
          width = 115,
          align = "center",
          header = with_tooltip(
            "Streak FGA", 
            paste("Total field goals attempted by the player after", streak_sel)
          ),
          style = color_scales(
            .,
            color_ref = "col_fga"
          ),
          filterMethod = filterMinValue
        ),
        streak_efg = colDef(
          name = "Streak eFG%",
          width = 130,
          align = "center",
          header = with_tooltip(
            "Streak eFG%", 
            paste("The player's effective field goal % after", streak_sel)
          ),
          style = color_scales(
            .,
            color_ref = "col_efg"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        base_efg = colDef(
          name = "Base eFG%",
          width = 115,
          align = "center",
          header = with_tooltip(
            "Base eFG%", 
            "The player's overall effective field goal %"
          ),
          style = color_scales(
            .,
            color_ref = "col_base"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        pct_open = colDef(
          name = "%FGA Open",
          align = "center",
          width = 120,
          header = with_tooltip(
            "%FGA Open", 
            paste("Player Open/Wide Open FGA frequency after", streak_sel)
          ),
          style = color_scales(
            .,
            color_ref = "col_pct"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        efg_open = colDef(
          name = "Open eFG%",
          align = "center",
          header = with_tooltip(
            "Open eFG%", 
            paste("Player's eFG% after", streak_sel, "on Open/Wide Open FGAs")
          ),
          width = 120,
          style = color_scales(
            .,
            color_ref = "col_open"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        efg_tight = colDef(
          name = "Tight eFG%",
          align = "center",
          width = 120,
          header = with_tooltip(
            "Tight eFG%", 
            paste("Player's eFG% after", streak_sel, "on Tight/Very Tight FGAs")
          ),
          style = color_scales(
            .,
            color_ref = "col_tight"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        coverage_diff = colDef(
          name = "Coverage &Delta;",
          width = 150,
          html = T,
          align = 'center',
          header = with_tooltip(
            "Coverage &Delta;",
            paste("Player's Tight eFG% &minus; Open eFG% after", streak_sel)
          ),
          cell = data_bars(
            ., 
            fill_color = c("lightblue", "orange"),
            number_fmt = scales::percent_format(accuracy = .1),
            bold_text = TRUE,
            img_ref = "icon_fg_diff",
            border_width = "thick",
            min_value = -1,
            max_value = 1,
            bar_height = 20,
            text_size = 13
          ),
          style = list(borderLeft = "1px dashed rgba(0, 0, 0, 0.3)")
        ),
        col_fga = colDef(show = FALSE),
        col_efg = colDef(show = FALSE),
        col_base = colDef(show = FALSE),
        col_pct = colDef(show = FALSE),
        col_open = colDef(show = FALSE),
        col_tight = colDef(show = FALSE),
        icon_fg_diff = colDef(show = FALSE)
      )
    )
}

# initial defender distance table
start_up_def_table <- function(dist_table, streak_sel) {
  
  
  # Reactable
  dist_table %>% 
    arrange(
      desc(streak_fga)
    ) %>% 
    reactable(
      elementId = "def-table-range",
      fullWidth = FALSE,
      language = reactableLang(
        noData = "No Shots Found"
      ),
      columnGroups = list(
        colGroup(
          name = "Player",
          columns = c("shooter", "headshot")
        )
      ),
      defaultPageSize = 10,
      class = "defender-table",
      striped = FALSE,
      borderless = TRUE,
      showSortIcon = TRUE,
      resizable = TRUE,
      bordered = FALSE,
      searchable = TRUE,
      defaultColDef = colDef(
        style = cell_style(font_weight = 500),
        align = "center"
      ),
      style = list(fontFamily = "Karla"),
      columns = list(
        headshot = colDef(
          name = "",
          width = 50,
          align = 'center',
          html = TRUE
        ),
        shooter = colDef(
          name = "",
          align = "left",
          style = cell_style(horizontal_align = "left"),
          width = 190
        ),
        streak_fga = colDef(
          name = "Streak FGA",
          width = 115,
          align = "center",
          header = with_tooltip(
            "Streak FGA", 
            paste("Total field goals attempted by the player after", streak_sel)
          ),
          style = color_scales(
            .,
            color_ref = "col_fga"
          ),
          filterMethod = filterMinValue
        ),
        streak_efg = colDef(
          name = "Streak eFG%",
          width = 130,
          align = "center",
          header = with_tooltip(
            "Streak eFG%", 
            paste("The player's effective field goal % after", streak_sel)
          ),
          style = color_scales(
            .,
            color_ref = "col_efg"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        base_efg = colDef(
          name = "Base eFG%",
          width = 115,
          align = "center",
          header = with_tooltip(
            "Base eFG%", 
            "The player's overall effective field goal %"
          ),
          style = color_scales(
            .,
            color_ref = "col_base"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        pct_open = colDef(
          name = "%FGA Open",
          align = "center",
          width = 120,
          header = with_tooltip(
            "%FGA Open", 
            paste("Player Open/Wide Open FGA frequency after", streak_sel)
          ),
          style = color_scales(
            .,
            color_ref = "col_pct"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        efg_open = colDef(
          name = "Open eFG%",
          align = "center",
          header = with_tooltip(
            "Open eFG%", 
            paste("Player's eFG% after", streak_sel, "on Open/Wide Open FGAs")
          ),
          width = 120,
          style = color_scales(
            .,
            color_ref = "col_open"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        efg_tight = colDef(
          name = "Tight eFG%",
          align = "center",
          width = 120,
          header = with_tooltip(
            "Tight eFG%", 
            paste("Player's eFG% after", streak_sel, "on Tight/Very Tight FGAs")
          ),
          style = color_scales(
            .,
            color_ref = "col_tight"
          ),
          format = colFormat(percent = TRUE, digits = 1)
        ),
        coverage_diff = colDef(
          name = "Coverage &Delta;",
          width = 150,
          html = T,
          align = 'center',
          header = with_tooltip(
            "Coverage &Delta;",
            paste("Player's Tight eFG% &minus; Open eFG% after", streak_sel)
          ),
          cell = data_bars(
            ., 
            fill_color = c("lightblue", "orange"),
            number_fmt = scales::percent_format(accuracy = .1),
            bold_text = TRUE,
            img_ref = "icon_fg_diff",
            border_width = "thick",
            min_value = -1,
            max_value = 1,
            bar_height = 20,
            text_size = 13
          ),
          style = list(borderLeft = "1px dashed rgba(0, 0, 0, 0.3)")
        ),
        col_fga = colDef(show = FALSE),
        col_efg = colDef(show = FALSE),
        col_base = colDef(show = FALSE),
        col_pct = colDef(show = FALSE),
        col_open = colDef(show = FALSE),
        col_tight = colDef(show = FALSE),
        icon_fg_diff = colDef(show = FALSE)
      )
    )
}
