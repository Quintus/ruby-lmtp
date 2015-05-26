$(document).ready(function(){

    /**
     * Hides/shows the complete list of files in the
     * file index. Also changes the toggle link’s text
     * accodingly.
     */
    $("a#toggle-all-files").click(function(event){
        $("li.code-file").toggle();

        if($(this).text() == "Show all")
            $(this).text("Hide extra");
        else
            $(this).text("Show all");

        return false;
    });

    /**
     * Hides/showes the sourcecode of a method, changing
     * the toggle link’s text accordingly.
     */
    $("p.show-source a").click(function(event){
        $(this).parent().next().toggle("slow");

        if ($(this).text() == "[Show source]")
            $(this).text("[Hide source]");
        else
            $(this).text("[Show source]");

        return false;
    });

    /**
     * Shows/hides the ¶ and ↑ anchor link signs next to
     * headings when hovering with the mouse over
     * a heading.
     */
    $("h1, h2, h3, h4, h5, h6").hover(
        function(event){
            $(this).find("span").last().find("a").show();
        },
        function(event){
            $(this).find("span").last().find("a").hide();
        }
    );

    // Hide all the ¶ and ↑ anchor link signs by default
    $("h1, h2, h3, h4, h5, h6").each(function(){
        $(this).find("span").last().find("a").hide();
    })

    /**
     * This code handles the search field, showing and hiding
     * matching/non-matching elements. When the search has ended,
     * i.e. the search field is empty again, restores the vanilla
     * status including hid of the code files in the file index.
     * A small problem with this is, if the file index had been
     * expanded by the user, it will now be collapsed again. However,
     * this should not be a major problem.
     *
     * The matches of the search expression are surrounded with a
     * <span class="search-result"> element, which is completely
     * removed when the search has ended.
     */
    $("form#search p input").keyup(function(event){
        // These are the lists we are going to iterate over
        // when searching for the user’s query.
        var targets = $("div#method-index ul li, div#class-index ul li, div#file-index ul li");

        // If the search field is empty, consider the search to
        // have been ended; restore original status.
        if ($(this).val().length == 0){
            // Show all elements (except for code file names, which
            // are hidden by default and shall return thereto).
            targets.each(function(index){
                // Remove any <span> element relicts
                var anchor = $(this).find("a");
                anchor.text(anchor.text()); // The text() getter works recursively, removing child structure nodes!

                // Show everything except for code files in the file index
                if ($(this).hasClass("code-file"))
                    $(this).hide();
                else
                    $(this).show();
            });

            // Ensure the "Show all" link for the file index shows
            // "Show all" now as we’ve hidden the code files above.
            $("a#toggle-all-files").text("Show all").show();

            // No need for further investigation
            return;
        }

        // Convert the user input into a Regular Expression.
        var term = new RegExp($(this).val(), "i");

        // Hide the "Show all/Hide extra" link when searching
        $("a#toggle-all-files").hide();

        // Iterate through all the lists and mark+show all matching
        // links. Hide those links that do not match.
        targets.each(function(index){
            var anchor = $(this).find("a");

            // Exclude the "Show all/Hide extra" link in the file
            // index from the search.
            if (anchor.attr("id") == "toggle-all-files")
                return true

            if (term.test(anchor.text())){
                anchor.html(anchor.text().replace(term, "<span class=\"search-result\">$&</span>"));
                $(this).show();
            }
            else
                $(this).hide();
        });
    });
});
