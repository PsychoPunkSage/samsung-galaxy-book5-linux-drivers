// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung Galaxy Book5 Pro MAX98390 GPIO Power Enable
 *
 * This module enables the GPIO power line for MAX98390 amplifiers
 * which is declared in ACPI but not automatically managed by the kernel.
 *
 * Copyright (c) 2026
 */

#include <linux/module.h>
#include <linux/acpi.h>
#include <linux/gpio/consumer.h>
#include <linux/platform_device.h>
#include <linux/delay.h>

#define DRIVER_NAME "max98390_gpio_enable"

struct max98390_gpio_data {
	struct gpio_desc *enable_gpio;
	struct device *dev;
};

static int max98390_gpio_probe(struct platform_device *pdev)
{
	struct max98390_gpio_data *data;
	struct gpio_desc *gpio;
	int ret;

	dev_info(&pdev->dev, "Probing MAX98390 GPIO enable driver\n");

	data = devm_kzalloc(&pdev->dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;

	data->dev = &pdev->dev;
	platform_set_drvdata(pdev, data);

	/*
	 * Get the GPIO from ACPI resources
	 * The GPIO should be declared in the MAX98390 ACPI device
	 * as GpioIo resource with index 0
	 */
	gpio = devm_gpiod_get_index(&pdev->dev, "enable", 0,
				    GPIOD_OUT_LOW);
	if (IS_ERR(gpio)) {
		ret = PTR_ERR(gpio);
		if (ret == -EPROBE_DEFER) {
			dev_info(&pdev->dev, "GPIO not ready, deferring probe\n");
			return ret;
		}

		dev_err(&pdev->dev, "Failed to get enable GPIO: %d\n", ret);

		/* Try alternative name */
		gpio = devm_gpiod_get_index(&pdev->dev, "amp-enable", 0,
					    GPIOD_OUT_LOW);
		if (IS_ERR(gpio)) {
			dev_err(&pdev->dev, "Failed to get amp-enable GPIO: %ld\n",
				PTR_ERR(gpio));
			return PTR_ERR(gpio);
		}
	}

	data->enable_gpio = gpio;

	/* Enable the amplifier power */
	gpiod_set_value_cansleep(data->enable_gpio, 1);
	dev_info(&pdev->dev, "MAX98390 power GPIO set to HIGH\n");

	/* Wait for device to power up */
	msleep(10);

	dev_info(&pdev->dev, "MAX98390 GPIO enable driver initialized successfully\n");
	return 0;
}

static int max98390_gpio_remove(struct platform_device *pdev)
{
	struct max98390_gpio_data *data = platform_get_drvdata(pdev);

	/* Optionally disable on removal (or leave powered) */
	if (data->enable_gpio) {
		/* Keep amplifier powered for now */
		dev_info(&pdev->dev, "MAX98390 GPIO enable driver removed (keeping power on)\n");
	}

	return 0;
}

static const struct acpi_device_id max98390_gpio_acpi_ids[] = {
	{ "MAX98390", 0 },
	{ "MXIM8390", 0 },
	{ }
};
MODULE_DEVICE_TABLE(acpi, max98390_gpio_acpi_ids);

static struct platform_driver max98390_gpio_driver = {
	.driver = {
		.name = DRIVER_NAME,
		.acpi_match_table = max98390_gpio_acpi_ids,
	},
	.probe = max98390_gpio_probe,
	.remove = max98390_gpio_remove,
};

module_platform_driver(max98390_gpio_driver);

MODULE_DESCRIPTION("Samsung Galaxy Book5 Pro MAX98390 GPIO Power Enable");
MODULE_AUTHOR("Samsung Galaxy Book5 Linux Driver Project");
MODULE_LICENSE("GPL");
