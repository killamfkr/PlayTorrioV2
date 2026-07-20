package com.playtorrio.tv.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.LiveTv
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.playtorrio.tv.R
import com.playtorrio.tv.data.AppContainer
import com.playtorrio.tv.ui.details.DetailsScreen
import com.playtorrio.tv.ui.home.HomeScreen
import com.playtorrio.tv.ui.iptv.IptvScreen
import com.playtorrio.tv.ui.search.SearchScreen
import com.playtorrio.tv.ui.settings.SettingsScreen
import com.playtorrio.tv.ui.theme.PtBg
import com.playtorrio.tv.ui.theme.PtSurface

sealed class Dest(val route: String) {
    data object Home : Dest("home")
    data object Search : Dest("search")
    data object Iptv : Dest("iptv")
    data object Settings : Dest("settings")
    data object Details : Dest("details/{mediaType}/{id}") {
        fun path(mediaType: String, id: Int) = "details/$mediaType/$id"
    }
}

@Composable
fun PlayTorrioNav(
    container: AppContainer,
    isTelevision: Boolean,
) {
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val current = backStack?.destination?.route
    val tabs = listOf(
        Dest.Home.route to (Icons.Outlined.Home to R.string.nav_home),
        Dest.Search.route to (Icons.Outlined.Search to R.string.nav_search),
        Dest.Iptv.route to (Icons.Outlined.LiveTv to R.string.nav_iptv),
        Dest.Settings.route to (Icons.Outlined.Settings to R.string.nav_settings),
    )
    val showBar = tabs.any { current == it.first }

    Scaffold(
        containerColor = PtBg,
        bottomBar = {
            if (showBar && !isTelevision) {
                NavigationBar(containerColor = PtSurface) {
                    tabs.forEach { (route, pair) ->
                        val (icon, label) = pair
                        NavigationBarItem(
                            selected = current == route,
                            onClick = {
                                nav.navigate(route) {
                                    popUpTo(Dest.Home.route) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(icon, contentDescription = null) },
                            label = { Text(stringResource(label)) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = nav,
            startDestination = Dest.Home.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(Dest.Home.route) {
                HomeScreen(
                    container = container,
                    isTelevision = isTelevision,
                    onOpen = { type, id -> nav.navigate(Dest.Details.path(type, id)) },
                    onOpenTab = { route -> nav.navigate(route) },
                )
            }
            composable(Dest.Search.route) {
                SearchScreen(
                    container = container,
                    isTelevision = isTelevision,
                    onOpen = { type, id -> nav.navigate(Dest.Details.path(type, id)) },
                    onOpenTab = { route -> nav.navigate(route) },
                )
            }
            composable(Dest.Iptv.route) {
                IptvScreen(
                    container = container,
                    isTelevision = isTelevision,
                    onOpenTab = { route -> nav.navigate(route) },
                )
            }
            composable(Dest.Settings.route) {
                SettingsScreen(
                    container = container,
                    isTelevision = isTelevision,
                    onOpenTab = { route -> nav.navigate(route) },
                )
            }
            composable(
                Dest.Details.route,
                arguments = listOf(
                    navArgument("mediaType") { type = NavType.StringType },
                    navArgument("id") { type = NavType.IntType },
                ),
            ) { entry ->
                DetailsScreen(
                    container = container,
                    mediaType = entry.arguments?.getString("mediaType") ?: "movie",
                    tmdbId = entry.arguments?.getInt("id") ?: 0,
                    isTelevision = isTelevision,
                    onBack = { nav.popBackStack() },
                )
            }
        }
    }
}
