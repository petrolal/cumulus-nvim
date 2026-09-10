return {
  {
    "sindrets/diffview.nvim",
    keys = {
      {
        "<leader>grp",
        function()
          require("tetravim.util.cloud.forge").list_and_review_prs()
        end,
        desc = "List & Review PRs (GitHub/GitLab)",
      },
      {
        "<leader>grc",
        function()
          require("tetravim.util.cloud.forge").checkout_pr()
        end,
        desc = "Checkout PR Branch",
      },
      {
        "<leader>grC",
        function()
          require("tetravim.util.cloud.forge").add_comment()
        end,
        desc = "Add PR Comment (Line)",
      },
    },
  },
}
