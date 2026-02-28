data:extend{
  {
		type = "bool-setting",
		name = "cheaper-recipes",
		setting_type = "startup",
		order = "a",
		default_value = true,
	},
	{
		type = "bool-setting",
		name = "double-stack-size",
		setting_type = "startup",
		order = "b1",
		default_value = true,
	},
  {
		type = "int-setting",
		name = "minimum-length",
		setting_type = "startup",
		order = "c",
		default_value = 0,
    minimum_value = 0,
    maximum_value = 30
	}
}