<!-- 
  TO DO
  --------------------
  Error handling for fetch
-->

<script setup>
import { ref, reactive, computed, onMounted } from "vue";

const traitData = ref(null);
const columnSorted = ref("color");
const sortOrder = ref("asc");
const filterString = ref("");
// dataSource is expected to eventually be an API endpoint
const dataSource = ref("/src/assets/dummy-data/traits.json");

const columnStatus = reactive({
  shape: false,
  color: true,
  total: false,
  remaining: false,
});

const sortedTraits = computed(() => {
  if (traitData.value) {
    let traitsArray = [];
    Object.entries(traitData.value).forEach((entry) => {
      traitsArray.push(entry[1]);
    });
    traitsArray.sort((a, b) => {
      if (a[columnSorted.value] < b[columnSorted.value]) {
        return -1;
      }
      if (a[columnSorted.value] > b[columnSorted.value]) {
        return 1;
      }
      return 0;
    });
    if (sortOrder.value == "desc") {
      traitsArray.reverse();
    }
    return traitsArray;
  }
});

const filteredTraits = computed(() => {
  const filteredList = new Map();
  if (sortedTraits.value) {
    Object.values(sortedTraits.value).forEach((value) => {
      if (
        value.shape.toLowerCase().includes(filterString.value.toLowerCase())
      ) {
        filteredList.set(value.color + "-" + value.shape, {
          shape: value.shape.charAt(0).toUpperCase() + value.shape.slice(1),
          color: value.color.charAt(0).toUpperCase() + value.color.slice(1),
          total: value.total,
          remaining: value.remaining,
          imageUrl: `/thumbnails/${value.color}-${value.shape}.png`,
        });
      }
    });
  }
  return filteredList;
});

async function fetchTraitData() {
  traitData.value = await (await fetch(dataSource.value)).json();
}

function toggleColumnSorted(column) {
  columnSorted.value = column;
  Object.keys(columnStatus).forEach((key) => {
    columnStatus[key] = key == column ? true : false;
  });
  sortOrder.value = sortOrder.value == "asc" ? "desc" : "asc";
}

onMounted(() => {
  fetchTraitData();
});
</script>

<template>
  <div class="p-4 h-full overflow-hidden">
    <div class="mt-4 pl-4">
      <span class="text-amber-500 font-bold pr-4">Search:</span>
      <input
        v-model="filterString"
        class="bg-zinc-400 border-2 border-red-900 text-black font-bold"
      />
    </div>
    <div
      class="
        mt-4
        p-4
        flex
        h-[90%]
        overflow-hidden
        bg-black
        border-2 border-red-900
        rounded-lg
      "
    >
      <div class="grow overflow-auto px-1">
        <table class="w-full">
          <thead class="sticky top-0 z-10 bg-black">
            <tr>
              <th
                @click="toggleColumnSorted('color')"
                :class="{ 'text-amber-500': columnStatus.color }"
                class="sticky top-0 z-10 border-b-2 border-amber-500"
              >
                <button class="font-bold">Color</button>
              </th>
              <th
                @click="toggleColumnSorted('shape')"
                :class="{ 'text-amber-500': columnStatus.shape }"
                class="sticky top-0 z-10 border-b-2 border-amber-500"
              >
                <button class="font-bold">Symbol</button>
              </th>
              <th class="sticky top-0 z-10 border-b-2 border-amber-500">
                &nbsp;
              </th>
              <!-- Header for optional 'total' column -->
              <!-- <th
                @click="toggleColumnSorted('total')"
                :class="{ 'text-amber-500': columnStatus.total }"
                class="sticky top-0 z-10 border-b-2 border-amber-500"
              >
                <button class="font-bold">Total</button>
              </th> -->
              <th
                @click="toggleColumnSorted('remaining')"
                :class="{ 'text-amber-500': columnStatus.remaining }"
                class="sticky top-0 z-10 border-b-2 border-amber-500"
              >
                <button class="font-bold">Remaining</button>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="trait in filteredTraits">
              <td class="border-t border-amber-500 text-center">
                {{ trait[1].color }}
              </td>
              <td class="border-t border-amber-500 text-center">
                {{ trait[1].shape }}
              </td>
              <td class="border-t border-amber-500 text-center">
                <img :src="trait[1].imageUrl" class="inline w-1/2 py-1" />
              </td>
              <!-- Optional 'total' column -->
              <!-- <td class="border-t border-amber-500 text-center">
                {{ trait[1].total }}
              </td> -->
              <td class="border-t border-amber-500 text-center">
                {{ trait[1].remaining }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
