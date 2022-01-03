
function clearForm(form) {
	for ( var i = 0; i < form.elements.length; ++i) {
		clearElement(form.elements[i]);
	}
}

function clearElement(element) {
	switch (element.type) {
	case "hidden":
	case "submit":
	case "reset":
	case "button":
	case "image":
		return;
	case "file":
		return;
	case "text":
	case "password":
	case "textarea":
		element.value = "";
		return;
	case "checkbox":
	case "radio":
		element.checked = false;
		return;
	case "select-one":
	case "select-multiple":
		element.selectedIndex = 0;
		return;
	default:
	}
}